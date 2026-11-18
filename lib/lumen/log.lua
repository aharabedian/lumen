--[[ lumen.log: what happened, kept 7 days in /home/lumen-log.cfg (next to lumen.cfg): switches going on and off
  and why, faults and heat trips, taps (with who tapped), alerts raised and cleared, LUMEN starting and stopping.
  Each event is added to the end of the file as it happens (one line, tab-separated); the file is rewritten
  only to drop what's older than 7 days.

  log.new(path, time) -> L          reads what's there (path nil: kept in memory only)
  L:add(time, kind, who, text, player?)   kind: "ON" "OFF" (a switch, and why), "FAULT" "CLEAR" "TRIP" "RESET",
                                    "HAND" (a mode set on the screen), "BAD" "WARN" (an alert raised) "GONE" (one
                                    cleared), "START" "STOP"; player: who tapped
  L.list = { { time, kind, who, text, player }... }   oldest first
  L:recent(filter) -> list           newest first; filter: "all" | "switches" (ON, OFF) | "faults" (FAULT, CLEAR,
                                    TRIP, RESET) | "hand" (anything someone tapped) | "alerts" (BAD, WARN, GONE)
  log.KEEP                          seconds kept (7 days)
]]

local log = {}

log.KEEP = 7 * 86400
local MAX = 600            -- events kept at most (an OpenComputers computer has little memory), whatever their age
local REWRITE = 1.5        -- the file is rewritten once it has this many times the events kept

local FILTERS = {
  switches = { ON = true, OFF = true },
  faults = { FAULT = true, CLEAR = true, TRIP = true, RESET = true },
  alerts = { BAD = true, WARN = true, GONE = true },
}

local L = {}
L.__index = L

local function clean(s) return (tostring(s or ""):gsub("[\t\r\n]", " ")) end

local function line(e)
  return table.concat({ ("%.0f"):format(e.time), e.kind, clean(e.who), clean(e.player), clean(e.text) }, "\t") .. "\n"
end

function log.new(path, time)
  local self = setmetatable({ path = path, list = {}, lines = 0 }, L)
  local f = path and io.open(path, "r")
  if f then
    for l in f:lines() do
      local t, kind, who, player, text = l:match("^([%d%.]+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
      if t then
        self.lines = self.lines + 1
        if tonumber(t) > time - log.KEEP then
          self.list[#self.list + 1] = { time = tonumber(t), kind = kind, who = who,
            player = player ~= "" and player or nil, text = text }
        end
      end
    end
    f:close()
  end
  for k, e in ipairs(self.list) do e.n = k end          -- in time order, as added when times tie
  table.sort(self.list, function(a, b) if a.time ~= b.time then return a.time < b.time end return a.n < b.n end)
  while #self.list > MAX do table.remove(self.list, 1) end
  if self.lines > #self.list * REWRITE + 50 then self:rewrite() end
  return self
end

function L:rewrite()
  if not self.path then return end
  local f = io.open(self.path .. ".tmp", "w")
  if not f then return end
  for _, e in ipairs(self.list) do f:write(line(e)) end
  f:close()
  os.remove(self.path)
  os.rename(self.path .. ".tmp", self.path)
  self.lines = #self.list
end

function L:add(time, kind, who, text, player)
  local e = { time = time, kind = kind, who = who or "", text = text or "", player = player }
  self.list[#self.list + 1] = e
  local cut = time - log.KEEP
  while #self.list > MAX or (self.list[1] and self.list[1].time <= cut) do table.remove(self.list, 1) end
  if self.path then
    local f = io.open(self.path, "a")
    if f then f:write(line(e)); f:close(); self.lines = self.lines + 1 end
    if self.lines > #self.list * REWRITE + 50 then self:rewrite() end
  end
  return e
end

function L:recent(filter)
  local want = FILTERS[filter]
  local out = {}
  for i = #self.list, 1, -1 do
    local e = self.list[i]
    if filter == "hand" then
      if e.player then out[#out + 1] = e end
    elseif not want or want[e.kind] then
      out[#out + 1] = e
    end
  end
  return out
end

return log
