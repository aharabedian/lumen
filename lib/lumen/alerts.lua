--[[ lumen.alerts: what's wrong with the power, from the readings. Alerts clear themselves when the
  condition goes away; there's nothing to acknowledge.

  alerts.evaluate(readings, cfg) -> { { id, level = "warn" | "bad", text }... }   bad first, then by id
    readings: lumen.power p:read(); cfg: lumen.config output. Per LSC (ids end in the LSC's address):
      offline:   can't be read                                          bad
      fill:      below cfg.criticalFill %                               bad
                 below cfg.lowFill %                                    warn
      drain:     at the cfg.drainAverage net ("1h": the LSC's 1 hour average, so a reactor's off cycles
                 don't count), empty within cfg.drainBadHours           bad
                                     empty within cfg.drainWarnHours    warn
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
local AVERAGE_TEXT = { ["5s"] = "5 s", ["5m"] = "5 min", ["1h"] = "1 h" }

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
      local secs = r.drain and r.drain[cfg.drainAverage]
      if secs then
        local level = secs < cfg.drainBadHours * 3600 and "bad" or secs < cfg.drainWarnHours * 3600 and "warn" or nil
        if level then
          add("drain" .. key, level, ("%s empty in %s (%s average)"):format(r.name, power.duration(secs),
            AVERAGE_TEXT[cfg.drainAverage]))
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
