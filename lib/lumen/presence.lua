--[[ lumen.presence: whether someone is at the screen, from whatever presence detector is attached. Only reads.

    OpenComputers' Motion Sensor ("motion_sensor"): a "motion" event when a living thing moves within 8 blocks in
      line of sight (players and mobs alike; its name comes with it). No polling, but nothing while it stands still.
    Computronics' Radar ("radar"): getPlayers(range) lists the players within range (8 at most, through walls).
      Polled; each call pauses the computer for half a second.
    OpenSecurity's Entity Detector ("os_entdetector"): scanPlayers(range) lists the players within half the range
      it's given (and keeps that half for the next call without one, so it's always given one). Polled.

  presence.new(component, cfg) -> p      cfg.wakeRange (blocks), cfg.wakePlayers (names; nil = anyone)
  p.kinds = { "motion sensor" | "radar" | "entity detector"... }   what's attached, for people
  p.polls                                 whether there's a radar or entity detector to ask
  p:poll() -> near, who                   asks them: near = a player within wakeRange (and in wakePlayers, if
                                          set); who = their name; nil, err when none answered
  p:motion(name) -> bool                  whether a motion event counts (anyone, or a name in wakePlayers)
  presence.scan(component) -> kinds       what's attached, without a config (lumen-setup)
]]

local presence = {}

local KINDS = { motion_sensor = "motion sensor", radar = "radar", os_entdetector = "entity detector" }
local ORDER = { "motion_sensor", "radar", "os_entdetector" }

function presence.scan(component)
  local out = {}
  for _, t in ipairs(ORDER) do
    if component.list(t, true)() then out[#out + 1] = KINDS[t] end
  end
  return out
end

local P = {}
P.__index = P

function presence.new(component, cfg)
  local self = setmetatable({ component = component, cfg = cfg, kinds = presence.scan(component), polled = {} }, P)
  for _, t in ipairs({ "radar", "os_entdetector" }) do
    for address in component.list(t, true) do self.polled[#self.polled + 1] = { type = t, address = address } end
  end
  self.polls = #self.polled > 0
  return self
end

function P:wanted(name)
  local list = self.cfg.wakePlayers
  if type(list) ~= "table" or #list == 0 then return true end
  for _, n in ipairs(list) do if n == name then return true end end
  return false
end

function P:motion(name) return self:wanted(name) end

function P:poll()
  local range = self.cfg.wakeRange or 6
  local answered, err = false, nil
  for _, d in ipairs(self.polled) do
    local proxy = self.component.proxy(d.address)
    if proxy then
      local ok, list, why
      if d.type == "radar" then
        ok, list, why = pcall(function() return proxy.getPlayers(range) end)
      else
        ok, list, why = pcall(function() return proxy.scanPlayers(range * 2) end)
      end
      if ok and type(list) == "table" then
        answered = true
        for _, e in pairs(list) do
          local dist = type(e) == "table" and (tonumber(e.distance) or tonumber(e.range)) or nil
          if dist and dist <= range and self:wanted(e.name) then return true, e.name end
        end
      else
        err = ok and tostring(why or list) or (tostring(list):gsub("^[^:]*:%d+: ", ""))
      end
    end
  end
  if answered then return false end
  return nil, err or "no presence detector answered"
end

return presence
