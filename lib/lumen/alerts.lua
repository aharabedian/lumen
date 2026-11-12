--[[ lumen.alerts: what's wrong with the power, from the readings. Alerts clear themselves when the condition
  goes away; there's nothing to acknowledge. Built not to cry wolf: each kind must last a while before it's
  raised (`hold`), clears only after a minute of being fine, and draining is judged against the switches.

  alerts.evaluate(readings, cfg, ctx?) -> { { id, level = "warn" | "bad", text, hold = seconds }... }
    bad first, then by id. readings: lumen.power p:read(); cfg: lumen.config output; ctx = { now, switches
    (lumen.control c.list), sources (lumen.sources s:read()), rate = fn(address, seconds) -> EU/t (history) }.
    Ids end in the LSC's address, or the source's or switch's name:
      offline   an LSC can't be read                                               bad    15 s
      fill      below cfg.criticalFill % / below cfg.lowFill %                     bad / warn  30 s
      drain     empty within cfg.drainBadHours / cfg.drainWarnHours, by alerts.drain   bad / warn  5 min
      maint     an LSC's maintenance isn't "ok"                                    warn   at once
      input     input over 5 min below (100 - cfg.inputDrop) % of the hour's (when set; not while a
                switch is off or switched in the last hour)                       warn   5 min
      loss      passive loss above cfg.maxPassiveLoss EU/t (when set)              warn   1 min
      source    a source can't be read                                             warn   30 s
      heat      a reactor at cfg.heatBad % / cfg.heatWarn % of its max heat        bad / warn  at once
      problems  a GT source reports maintenance problems                           warn   1 min
      stopped   an alwaysOn source isn't running (not while its switch is off)     warn   5 min
      switch    a switch can't be found or switched                                bad    15 s
      running   a switch is on but its source isn't running, or off but it is      warn   5 min
    and "none" (warn) when no LSC was found.
  alerts.drain(reading, cfg, ctx) -> seconds | nil, how
    How long until the LSC is empty, as the drain alerts judge it, and how ("1 h average", "draining with
    Vac nuke on"). With switches covering the LSC (its own, or ones following all LSCs):
      one is off in auto     nil, "standby": draining is expected, it comes on at its mark
      all on                 the rate since the last one came on (from 10 min on; up to the last hour)
      one is off by hand     as without switches
    Without: the LSC's cfg.drainAverage net.
  alerts.tracker() -> t
    t:update(list, now) -> new   raises an alert once it has lasted its hold (a.since: when it started); keeps it
                                 a minute after it clears. new: ids just raised, or gone from warn to bad
    t.list                       what's raised now, each with since
  alerts.health(list) -> "ok" | "warn" | "bad"
]]

local power = require("lumen.power")

local alerts = {}

local RANK = { bad = 1, warn = 2 }
local AVERAGE_TEXT = { ["5s"] = "5 s", ["5m"] = "5 min", ["1h"] = "1 h" }
local SETTLE = 600       -- seconds switches must be on before their rate counts
local CLEAR = 60         -- seconds an alert stays after its condition goes
local TICKS = 20

local function covering(r, ctx)
  local out = {}
  for _, s in ipairs(ctx and ctx.switches or {}) do
    if not s.err and s.on ~= nil and (s.lsc == nil or s.lsc == r.name) then out[#out + 1] = s end
  end
  return out
end

function alerts.drain(r, cfg, ctx)
  local list = covering(r, ctx)
  if #list > 0 then
    local manualOff, latest, names = false, -math.huge, {}
    for _, s in ipairs(list) do
      if not s.on then
        if s.mode == "auto" then return nil, "standby" end
        manualOff = true
      end
      latest = math.max(latest, s.since or -math.huge)
      names[#names + 1] = s.name
    end
    if not manualOff then
      local onFor = ctx.now - latest
      if onFor < SETTLE then return nil, "settling" end
      local net = ctx.rate and ctx.rate(r.address, math.min(onFor, 3600))
      if not (net and net < 0 and r.stored) then return nil, "keeping up" end
      return r.stored / -net / TICKS, "draining with " .. table.concat(names, " and ") .. " on"
    end
  end
  return r.drain and r.drain[cfg.drainAverage], AVERAGE_TEXT[cfg.drainAverage] .. " average"
end

local function lscAlerts(r, cfg, ctx, add)
  local key = ":" .. r.address
  if not r.ok then
    add("offline" .. key, "bad", ("%s can't be read: %s"):format(r.name, tostring(r.err)), 15)
    return
  end
  local pct = r.fill and r.fill * 100
  if pct and pct < cfg.criticalFill then
    add("fill" .. key, "bad", ("%s nearly empty: %.1f%%"):format(r.name, pct), 30)
  elseif pct and pct < cfg.lowFill then
    add("fill" .. key, "warn", ("%s low: %.1f%%"):format(r.name, pct), 30)
  end
  local secs, how = alerts.drain(r, cfg, ctx)
  if secs then
    local level = secs < cfg.drainBadHours * 3600 and "bad" or secs < cfg.drainWarnHours * 3600 and "warn" or nil
    if level then
      add("drain" .. key, level, ("%s empty in %s (%s)"):format(r.name, power.duration(secs), how), 300)
    end
  end
  if r.maintenance and r.maintenance ~= "ok" then
    add("maint" .. key, "warn", ("%s needs maintenance (%s)"):format(r.name, r.maintenance), 0)
  end
  if cfg.inputDrop and r.in1h and r.in5m and r.in1h > 0 and r.in5m < r.in1h * (1 - cfg.inputDrop / 100) then
    local quiet = true
    for _, s in ipairs(covering(r, ctx)) do
      if not s.on or ctx.now - (s.since or -math.huge) < 3600 then quiet = false end
    end
    if quiet then
      add("input" .. key, "warn", ("%s input down to %s EU/t (%s over the hour)"):format(r.name,
        power.si(r.in5m), power.si(r.in1h)), 300)
    end
  end
  if cfg.maxPassiveLoss and r.passiveLoss and r.passiveLoss > cfg.maxPassiveLoss then
    add("loss" .. key, "warn", ("%s passive loss %s EU/t"):format(r.name, power.si(r.passiveLoss)), 60)
  end
end

local function sourceAlerts(src, cfg, ctx, add)
  local key = ":" .. src.name
  if not src.ok then
    add("source" .. key, "warn", ("%s can't be read: %s"):format(src.name, tostring(src.err)), 30)
    return
  end
  if src.heat then
    local pct = src.heat * 100
    if pct >= cfg.heatBad then add("heat" .. key, "bad", ("%s heat %.0f%%"):format(src.name, pct), 0)
    elseif pct >= cfg.heatWarn then add("heat" .. key, "warn", ("%s heat %.0f%%"):format(src.name, pct), 0) end
  end
  if src.problems and src.problems > 0 then
    add("problems" .. key, "warn", ("%s needs maintenance (%d problem%s)"):format(src.name, src.problems,
      src.problems == 1 and "" or "s"), 60)
  end
  if src.alwaysOn and not src.active then
    local switchedOff = false
    for _, s in ipairs(ctx.switches or {}) do if s.source == src.name and s.on == false then switchedOff = true end end
    if not switchedOff then add("stopped" .. key, "warn", src.name .. " stopped", 300) end
  end
end

local function switchAlerts(s, ctx, add)
  local key = ":" .. s.name
  if s.err then
    add("switch" .. key, "bad", ("%s can't be switched: %s"):format(s.name, s.err), 15)
    return
  end
  if not s.source or s.on == nil then return end
  for _, src in ipairs(ctx.sources or {}) do
    if src.name == s.source and src.ok then
      if s.on and not src.active then
        add("running" .. key, "warn", ("%s is switched on but %s isn't running"):format(s.name, src.name), 300)
      elseif not s.on and src.active then
        add("running" .. key, "warn", ("%s is switched off but %s is still running"):format(s.name, src.name), 300)
      end
    end
  end
end

function alerts.evaluate(readings, cfg, ctx)
  ctx = ctx or { now = 0 }
  local out = {}
  local function add(id, level, text, hold) out[#out + 1] = { id = id, level = level, text = text, hold = hold } end
  if #readings == 0 then add("none", "warn", "No LSC found: put an adapter on an LSC's controller", 0) end
  for _, r in ipairs(readings) do lscAlerts(r, cfg, ctx, add) end
  for _, src in ipairs(ctx.sources or {}) do sourceAlerts(src, cfg, ctx, add) end
  for _, s in ipairs(ctx.switches or {}) do switchAlerts(s, ctx, add) end
  table.sort(out, function(a, b)
    if a.level ~= b.level then return RANK[a.level] < RANK[b.level] end
    return a.id < b.id
  end)
  return out
end

function alerts.health(list)
  local worst = "ok"
  for _, a in ipairs(list) do
    if a.level == "bad" then return "bad" end
    worst = "warn"
  end
  return worst
end

local T = {}
T.__index = T

function alerts.tracker()
  return setmetatable({ first = {}, shown = {}, seen = {}, list = {} }, T)
end

local function order(a, b)
  if a.level ~= b.level then return RANK[a.level] < RANK[b.level] end
  return a.id < b.id
end

function T:update(list, now)
  local new, present = {}, {}
  for _, a in ipairs(list) do
    present[a.id] = true
    self.first[a.id] = self.first[a.id] or now
    self.seen[a.id] = now
    a.since = self.first[a.id]
    local was = self.shown[a.id]
    if was or now - a.since >= (a.hold or 0) then
      if not was or RANK[a.level] < RANK[was.level] then new[#new + 1] = a.id end
      self.shown[a.id] = a
    end
  end
  for id in pairs(self.first) do
    if not present[id] and (not self.shown[id] or now - self.seen[id] >= CLEAR) then
      self.shown[id], self.first[id], self.seen[id] = nil, nil, nil
    end
  end
  local out = {}
  for _, a in pairs(self.shown) do out[#out + 1] = a end
  table.sort(out, order)
  self.list = out
  return new
end

return alerts
