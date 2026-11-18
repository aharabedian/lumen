--[[ lumen.presence: whether someone is at the screen, from a Computronics Radar block ("radar") touching the
  computer or cabled to it. Only reads. getPlayers(range) lists the players within range (8 at most, through
  walls); each call pauses the computer for half a second, so lumen.app asks only in big mode and just before.

  presence.new(component, cfg) -> p      cfg.wakeRange (blocks), cfg.wakePlayers (names; nil = anyone)
  p.kinds = { "radar" } | {}              what's attached, for people
  p.polls                                 whether there's a radar to ask
  p:poll() -> near, who                   near = a player within wakeRange (and in wakePlayers, if set);
                                          who = their name; nil, err when no radar answered
  presence.scan(component) -> kinds       what's attached, without a config (lumen-setup)
]]

local presence = {}

function presence.scan(component)
  if component.list("radar", true)() then return { "radar" } end
  return {}
end

local P = {}
P.__index = P

function presence.new(component, cfg)
  local self = setmetatable({ component = component, cfg = cfg, kinds = presence.scan(component), radars = {} }, P)
  for address in component.list("radar", true) do self.radars[#self.radars + 1] = address end
  self.polls = #self.radars > 0
  return self
end

function P:wanted(name)
  local list = self.cfg.wakePlayers
  if type(list) ~= "table" or #list == 0 then return true end
  for _, n in ipairs(list) do if n == name then return true end end
  return false
end

function P:poll()
  local range = self.cfg.wakeRange or 6
  local answered, err = false, nil
  for _, address in ipairs(self.radars) do
    local proxy = self.component.proxy(address)
    if proxy then
      local ok, list = pcall(function() return proxy.getPlayers(range) end)
      if ok and type(list) == "table" then
        answered = true
        for _, e in pairs(list) do
          local dist = type(e) == "table" and tonumber(e.distance) or nil
          if dist and dist <= range and self:wanted(e.name) then return true, e.name end
        end
      else
        err = ok and tostring(list) or (tostring(list):gsub("^[^:]*:%d+: ", ""))
      end
    end
  end
  if answered then return false end
  return nil, err or "no radar answered"
end

return presence
