--[[ lumen.control: switching generators on and off with the LSCs' fill. Each cfg.control entry is a switch:
  a redstone output (`redstone` = the start of a Redstone I/O block's or card's address, `side`, `invert`,
  `strength`), or a GT machine's work switch (`machine` = the start of its address; never an LSC). Only what the
  config names is ever switched. A switch may have a fault input (`fault` = { redstone, side, invert, latch,
  stop }): a redstone signal from whatever it runs that means trouble. LUMEN only reads it.

  control.SIDES                       side names -> OpenComputers side numbers (bottom 0 ... east 5)
  control.new(component, cfg, kept?) -> c
    kept: what c:modes(), c:faults(), c:trips() and c:groupSteps() returned last run (lumen.state), as
    { modes = { [switch] = "on" | "off" }, faults = { [switch] = true }, trips = { [switch] = why | { rearm } },
      groups = { [group] = { step active... } } }; switches not in modes start in "auto"
  c:update(readings, total, now, extra?)   decide, switch, read back; fills c.list and c.groups
    extra = { sources = lumen.sources list (for heat trips), onTime = { [switch] = seconds on, last 24 h }
              (a group starts the least first) }
  c.list = { {
      name, index (in cfg.control), mode = "auto" | "on" | "off", on = bool | nil (nil: can't tell), since (now
      when it last switched, or when LUMEN started), onBelow, offAbove (nil for a group's member without its
      own, or always on), lsc (name followed; nil: all LSCs; a member follows its group's), source (name),
      group (name), always (bool: on unless set OFF on the screen),
      fill (0..1 it follows, nil when unreadable), why (a few words: "below 30%", "holding: LSC unreadable",
      "standing by: 1 of 4 needed", "always on"), err (text: can't be found or switched),
      fault = nil (no fault input) | { on (a fault now: the signal, or latched), signal (bool; nil: unreadable),
        latched, since (when it began), err (text: the input can't be read) },
      trip = nil (no heatTrip or heatRise) | { on, why ("heat 91%, trips at 90%"), since, heat (% now, nil when
        its source can't be read), rearm (% it trips at after a RESET above heatTrip, until it cools) } }... }
    in cfg.control order
  c.groups = { { name, lsc, rotate, fill, need (how many it wants on; nil before the first decision), running
      (members on in auto), why, steps = { { onBelow, offAbove, run, active }... }, members = { switch... },
      order = { switch... } (who starts next first: least run time, or cfg.control order without rotate),
      hours = { [switch] = seconds on in 24 h } }... }   in cfg.groups order
  c:setMode(name, mode, now)          from the screen: "auto", "on" or "off"; manual modes switch at once
  c:modes() -> { [name] = mode }      the manual ones, to keep across restarts
  c:reset(name, now)                  RESET on the screen: clears a latched fault once its signal is gone, and a
                                      heat trip; switches at once
  c:faults() -> { [name] = true }     the latched faults, to keep across restarts
  c:trips() -> { [name] = why | { rearm = % } }   heat trips and raised marks after a RESET, to keep across
                                      restarts
  c:groupSteps() -> { [group] = { bool... } }   which steps are on, to keep across restarts

  A fault (with stop, the default) switches off at once, whatever the mode, and holds it off while it lasts;
  once it clears, auto waits minSwitch as after any switch. latch: a fault stays until RESET. A fault input
  that can't be read is an error on the fault, and switches nothing.

  Heat trip (heatTrip: % of the source's max heat; heatRise: % of max heat a minute, over at least 30 s): switches
  off at once whatever the mode and stays tripped until RESET. A RESET while the heat is still at or over
  heatTrip lets it run (a reactor only cools while it runs) and trips 5 points higher until it falls below
  heatTrip. A source that can't be read trips nothing.

  always: on whenever it isn't set OFF on the screen, faulted or tripped (after a fault or a trip, it waits
  minSwitch before running again); no marks.

  Auto: on below onBelow %, off above offAbove %, unchanged in between (so it doesn't flicker). It waits
  minSwitch seconds (default 60) after switching before switching again, and holds while it can't read the fill. On start it
  reads the output as it is, so a restart never flips anything. Each update reads the output back and sets it
  again if it differs (a redstone output resets when its chunk reloads).

  A group's members in auto switch by the group instead: each step is on below its onBelow and off above its
  offAbove, and the group wants the sum of its steps' run. A step in its band keeps what it was (after a restart
  without that, what's running says). Too few on: the members off with the least run time start (cfg.control
  order without rotate); too many: the most run time stops. A member set ON or OFF by hand, faulted, tripped or
  broken is left out, and the next takes its place; each still waits its own minSwitch.
]]

local power = require("lumen.power")

local control = {}

control.SIDES = { bottom = 0, down = 0, top = 1, up = 1, north = 2, back = 2, south = 3, front = 3,
  west = 4, right = 4, east = 5, left = 5 }

local C = {}
C.__index = C

local function reason(err) return (tostring(err):gsub("^[^:]*:%d+: ", "")) end

function control.new(component, cfg, kept)
  kept = type(kept) == "table" and kept or {}
  local modes, faults = kept.modes or {}, kept.faults or {}
  local trips, steps = kept.trips or {}, kept.groups or {}
  local self = setmetatable({ component = component, cfg = cfg, list = {}, groups = {}, at = {} }, C)
  local byName = {}
  for _, g in ipairs(cfg.groups or {}) do
    local saved = type(steps[g.name]) == "table" and steps[g.name] or {}
    local G = { name = g.name, cfg = g, lsc = g.lsc, rotate = g.rotate ~= false, steps = {}, members = {}, order = {},
      hours = {} }
    for k, st in ipairs(g.steps) do
      local was = saved[k]
      G.steps[k] = { onBelow = st.onBelow, offAbove = st.offAbove, run = st.run,
        active = (was == true or was == false) and was or nil }
    end
    self.groups[#self.groups + 1] = G
    byName[g.name] = G
  end
  for i, sw in ipairs(cfg.control or {}) do
    local mode = modes[sw.name]
    local latched = sw.fault and sw.fault.latch and faults[sw.name] == true or false
    local G = sw.group and byName[sw.group]
    local s = { name = sw.name, index = i, mode = (mode == "on" or mode == "off") and mode or "auto",
      onBelow = sw.onBelow, offAbove = sw.offAbove, lsc = G and G.lsc or sw.lsc, source = sw.source,
      group = G and G.name or nil, always = sw.always == true and not G or nil, cfg = sw,
      fault = sw.fault and { on = latched, latched = latched } or nil }
    if sw.heatTrip or sw.heatRise then
      local kept1 = trips[sw.name]
      local why = type(kept1) == "string" and kept1 or nil
      local rearm = type(kept1) == "table" and tonumber(kept1.rearm) or nil
      s.trip = { on = why ~= nil, why = why, rearm = rearm, samples = {} }
    end
    self.list[#self.list + 1] = s
    if G then G.members[#G.members + 1] = s end
  end
  return self
end

-- The component (address and proxy) whose address starts with `prefix`, of type `ctype`.
function C:resolve(prefix, ctype)
  local cached = self.at[prefix]
  if cached and self.component.proxy(cached) then return cached, self.component.proxy(cached) end
  for address in self.component.list(ctype, true) do
    if address:sub(1, #prefix) == prefix then
      self.at[prefix] = address
      return address, self.component.proxy(address)
    end
  end
end

local function sideOf(sw)
  if type(sw.side) == "number" then return sw.side end
  return control.SIDES[sw.side]
end

-- The output as it is: true (generators on), false, or nil, err.
function C:readOutput(s)
  local sw = s.cfg
  if sw.redstone then
    local _, proxy = self:resolve(sw.redstone, "redstone")
    if not proxy then return nil, "no redstone component at " .. sw.redstone end
    local ok, v = pcall(proxy.getOutput, sideOf(sw))
    if not ok then return nil, reason(v) end
    return ((tonumber(v) or 0) > 0) ~= (sw.invert == true)
  end
  local _, proxy = self:resolve(sw.machine, "gt_machine")
  if not proxy then return nil, "no GT machine at " .. sw.machine end
  local okName, name = pcall(proxy.getName)
  if okName and name == power.LSC then return nil, "that's an LSC: LUMEN never switches LSCs" end
  local ok, v = pcall(proxy.isWorkAllowed)
  if not ok then return nil, reason(v) end
  return v and true or false
end

-- The fault input: true (trouble), false, or nil, err.
function C:readFault(s)
  local f = s.cfg.fault
  local _, proxy = self:resolve(f.redstone, "redstone")
  if not proxy then return nil, "no redstone component at " .. f.redstone end
  local ok, v = pcall(proxy.getInput, sideOf(f))
  if not ok then return nil, reason(v) end
  return ((tonumber(v) or 0) > 0) ~= (f.invert == true)
end

function C:checkFault(s, now)
  local f = s.fault
  if not f then return end
  f.signal, f.err = self:readFault(s)
  if f.signal and s.cfg.fault.latch then f.latched = true end
  local on = f.signal == true or f.latched
  if on and (not f.on or not f.since) then f.since = now end   -- a latched fault kept from the last run: from now
  f.on = on
end

local RISE_WINDOW, RISE_MIN, REARM = 60, 30, 5

local function checkTrip(s, src, now)
  local t = s.trip
  if not t then return end
  t.heat = (src and src.ok and src.heat) and src.heat * 100 or nil
  if t.on then t.since = t.since or now; return end   -- latched until RESET (one kept from the last run: from now)
  if not t.heat then return end
  local pct = t.heat
  local sw, samples = s.cfg, t.samples
  samples[#samples + 1] = { now, pct }
  while #samples > 2 and now - samples[2][1] >= RISE_WINDOW do table.remove(samples, 1) end
  if t.rearm and sw.heatTrip and pct < sw.heatTrip then t.rearm = nil end   -- cooled: back to the usual mark
  local mark = t.rearm or sw.heatTrip
  local why
  if mark and pct >= mark then
    why = ("heat %.0f%%, trips at %g%%"):format(pct, mark)
  elseif sw.heatRise and now - samples[1][1] >= RISE_MIN then
    local rate = (pct - samples[1][2]) / (now - samples[1][1]) * 60
    if rate >= sw.heatRise then why = ("heat rising %.1f%% a minute, trips at %g%%"):format(rate, sw.heatRise) end
  end
  if why then t.on, t.why, t.since = true, why, now end
end

function C:writeOutput(s, on)
  local sw = s.cfg
  if sw.redstone then
    local _, proxy = self:resolve(sw.redstone, "redstone")
    local level = (on ~= (sw.invert == true)) and (sw.strength or 15) or 0
    local ok, err = pcall(proxy.setOutput, sideOf(sw), level)
    return ok, not ok and reason(err) or nil
  end
  local _, proxy = self:resolve(sw.machine, "gt_machine")
  local ok, err = pcall(proxy.setWorkAllowed, on)
  return ok, not ok and reason(err) or nil
end

-- The reading a switch follows: the LSC it names, else the total, else the only LSC.
local function followed(s, readings, total)
  if s.lsc then
    for _, r in ipairs(readings) do if r.name == s.lsc then return r end end
    return nil
  end
  return total or (#readings == 1 and readings[1]) or nil
end

local function stopped(s)
  return (s.trip and s.trip.on) or (s.fault and s.fault.on and s.cfg.fault.stop)
end

local function decide(s, now, force)
  if s.trip and s.trip.on then return false, "heat trip" end
  if s.fault and s.fault.on and s.cfg.fault.stop then return false, "fault: stopped" end
  if s.always and s.mode ~= "off" then
    if not force and s.on == false and s.switched and now - s.switched < (s.cfg.minSwitch or 60) then
      return false, "waiting to switch again"
    end
    return true, "always on"
  end
  if s.mode ~= "auto" then return s.mode == "on", "set " .. s.mode:upper() .. " on the screen" end
  if s.group then
    if s.groupWant ~= nil then return s.groupWant, s.groupWhy end
    return s.on, s.groupWhy or ("group " .. s.group)
  end
  if s.fill == nil then return s.on, "holding: can't read the LSC" end
  local pct = s.fill * 100
  local want, why = s.on, ("between %g%% and %g%%"):format(s.onBelow, s.offAbove)
  if pct < s.onBelow then want, why = true, ("below %g%%"):format(s.onBelow)
  elseif pct > s.offAbove then want, why = false, ("above %g%%"):format(s.offAbove) end
  if not force and want ~= s.on and s.on ~= nil and now - (s.switched or -math.huge) < (s.cfg.minSwitch or 60) then
    return s.on, "waiting to switch again"
  end
  if want == nil then want = true end      -- output unknown and between the marks: power first
  return want, why
end

function C:apply(s, now, force)
  local actual, err = self:readOutput(s)
  if actual == nil then s.on, s.err = nil, err; return end
  s.err = nil
  if s.on == nil then s.on, s.since = actual, s.since or now end   -- first look: as it is
  local want
  want, s.why = decide(s, now, force)
  if want == nil then return end
  if want ~= actual then
    local ok, werr = self:writeOutput(s, want)
    if not ok then s.err = werr; return end
  end
  if want ~= s.on then s.since, s.switched = now, now end
  s.on = want
end

local function ready(s, now) return now - (s.switched or -math.huge) >= (s.cfg.minSwitch or 60) end

-- Which members a group starts or stops this time: sets each member's groupWant (nil: leave it) and groupWhy.
local function decideGroup(g, readings, total, now, onTime)
  local r = followed(g, readings, total)
  g.fill = (r and r.ok and r.fill) or nil
  local hours = {}
  for _, s in ipairs(g.members) do
    s.groupWant, s.groupWhy = nil, nil
    hours[s.name] = onTime and onTime[s.name] or 0
  end
  g.hours = hours
  local function first(a, b)          -- who starts first
    if g.rotate and hours[a.name] ~= hours[b.name] then return hours[a.name] < hours[b.name] end
    return a.index < b.index
  end
  local order = { table.unpack(g.members) }
  table.sort(order, first)
  g.order = order
  local pool, running = {}, 0
  for _, s in ipairs(order) do
    if s.mode == "auto" and s.on ~= nil and not s.err and not stopped(s) then
      pool[#pool + 1] = s
      if s.on then running = running + 1 end
    end
  end
  g.running = running
  if g.fill == nil then
    g.why = "holding: can't read the LSC"
    for _, s in ipairs(g.members) do s.groupWhy = g.why end
    return
  end
  local pct, need, cum = g.fill * 100, 0, 0
  for _, st in ipairs(g.steps) do
    cum = cum + st.run
    if pct < st.onBelow then st.active = true
    elseif pct > st.offAbove then st.active = false
    elseif st.active == nil then st.active = running >= cum end   -- after a restart: what's running says
    if st.active then need = need + st.run end
  end
  g.need = need
  g.why = ("%d needed"):format(need)
  local of = ("%d of %d needed"):format(need, #g.members)
  for _, s in ipairs(pool) do s.groupWhy = s.on and of or ("standing by: " .. of) end
  if running < need then
    local k = need - running
    for _, s in ipairs(pool) do
      if k == 0 then break end
      if not s.on then
        if ready(s, now) then s.groupWant, s.groupWhy = true, "starting: " .. of
        else s.groupWhy = "waiting to switch again" end
        k = k - 1
      end
    end
  elseif running > need then
    local k = running - need
    for i = #pool, 1, -1 do
      local s = pool[i]
      if k == 0 then break end
      if s.on and ready(s, now) then
        s.groupWant, s.groupWhy = false, "stopping: " .. of
        k = k - 1
      end
    end
  end
end

function C:update(readings, total, now, extra)
  extra = extra or {}
  local srcs = {}
  for _, src in ipairs(extra.sources or {}) do srcs[src.name] = src end
  for _, s in ipairs(self.list) do
    local r = followed(s, readings, total)
    s.fill = (r and r.ok and r.fill) or nil
    self:checkFault(s, now)
    checkTrip(s, s.source and srcs[s.source], now)
  end
  if self.looked then    -- the first look only reads the outputs as they are
    for _, g in ipairs(self.groups) do decideGroup(g, readings, total, now, extra.onTime) end
  end
  for _, s in ipairs(self.list) do self:apply(s, now) end
  for _, g in ipairs(self.groups) do        -- what's running now, after this update's switching
    local n = 0
    for _, s in ipairs(g.members) do if s.on and s.mode == "auto" and not stopped(s) then n = n + 1 end end
    g.running = n
  end
  self.looked = true
  return self.list
end

function C:setMode(name, mode, now)
  for _, s in ipairs(self.list) do
    if s.name == name and (mode == "auto" or mode == "on" or mode == "off") then
      s.mode = mode
      self:apply(s, now, true)           -- a choice on the screen doesn't wait for minSwitch
    end
  end
end

function C:reset(name, now)
  for _, s in ipairs(self.list) do
    if s.name == name then
      local t, any = s.trip, false
      if s.fault and s.fault.latched then
        s.fault.latched, any = false, true
        self:checkFault(s, now)
      end
      if t and t.on then
        t.on, t.why, t.since, t.samples, any = false, nil, nil, {}, true
        local mark = s.cfg.heatTrip
        if mark and t.heat and t.heat >= mark then t.rearm = math.min(100, t.heat + REARM) end
      end
      if any then self:apply(s, now, true) end
    end
  end
end

function C:trips()
  local out = {}
  for _, s in ipairs(self.list) do
    local t = s.trip
    if t and t.on then out[s.name] = t.why elseif t and t.rearm then out[s.name] = { rearm = t.rearm } end
  end
  return out
end

function C:groupSteps()
  local out = {}
  for _, g in ipairs(self.groups) do
    local t = {}
    for k, st in ipairs(g.steps) do t[k] = st.active == true end
    out[g.name] = t
  end
  return out
end

function C:faults()
  local out = {}
  for _, s in ipairs(self.list) do if s.fault and s.fault.latched then out[s.name] = true end end
  return out
end

function C:modes()
  local out = {}
  for _, s in ipairs(self.list) do if s.mode ~= "auto" then out[s.name] = s.mode end end
  return out
end

return control
