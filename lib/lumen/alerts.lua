--[[ lumen.alerts: what's wrong with the power, from the readings. Alerts clear themselves when the
  condition goes away; there's nothing to acknowledge.

  alerts.evaluate(readings, cfg) -> { { id, level = "warn" | "bad", text }... }   bad first, then by id
    readings: lumen.power p:read(); cfg: lumen.config output. Per LSC (ids end in the LSC's address):
      offline:   can't be read                                          bad
      fill:      below cfg.criticalFill %                               bad
                 below cfg.lowFill %                                    warn
      drain:     emptying, empty within cfg.drainBadHours               bad
                 emptying, empty within cfg.drainWarnHours              warn
      maint:     maintenance isn't "ok"                                 warn
    and "none" (warn) when no LSC was found.
  alerts.tracker() -> t
    t:update(list, now) -> new   remembers when each alert started (a.since); new: the ids that just appeared
                                 or got worse (warn to bad)
    t.list                       the latest list, each with since
  alerts.health(list) -> "ok" | "warn" | "bad"
]]

local power = require("lumen.power")

local alerts = {}

local RANK = { bad = 1, warn = 2 }

function alerts.evaluate(readings, cfg)
  local out = {}
  local function add(id, level, text) out[#out + 1] = { id = id, level = level, text = text } end
  if #readings == 0 then add("none", "warn", "No LSC found: put an adapter on an LSC's controller") end
  for _, r in ipairs(readings) do
    local key = ":" .. r.address
    if not r.ok then
      add("offline" .. key, "bad", ("%s can't be read: %s"):format(r.name, tostring(r.err)))
    else
      local pct = r.fill and r.fill * 100
      if pct and pct < cfg.criticalFill then
        add("fill" .. key, "bad", ("%s nearly empty: %.1f%%"):format(r.name, pct))
      elseif pct and pct < cfg.lowFill then
        add("fill" .. key, "warn", ("%s low: %.1f%%"):format(r.name, pct))
      end
      if r.empty then
        local hours = r.empty / 3600
        if hours < cfg.drainBadHours then
          add("drain" .. key, "bad", ("%s empty in %s"):format(r.name, power.duration(r.empty)))
        elseif hours < cfg.drainWarnHours then
          add("drain" .. key, "warn", ("%s empty in %s"):format(r.name, power.duration(r.empty)))
        end
      end
      if r.maintenance and r.maintenance ~= "ok" then
        add("maint" .. key, "warn", ("%s needs maintenance (%s)"):format(r.name, r.maintenance))
      end
    end
  end
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

function alerts.tracker() return setmetatable({ since = {}, level = {}, list = {} }, T) end

function T:update(list, now)
  local since, level, new = {}, {}, {}
  for _, a in ipairs(list) do
    since[a.id], level[a.id] = self.since[a.id] or now, a.level
    local was = self.level[a.id]
    if not was or RANK[a.level] < RANK[was] then new[#new + 1] = a.id end
    a.since = since[a.id]
  end
  self.since, self.level, self.list = since, level, list
  return new
end

return alerts
