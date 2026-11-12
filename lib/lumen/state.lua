--[[ lumen.state: what LUMEN keeps between runs, in /home/lumen-state.cfg (next to lumen.cfg): the switches set
  ON or OFF on the screen, and history. Not a settings file: LUMEN rewrites it.

  state.clock(filesystem, computer, path) -> c
    c:now() -> seconds        real seconds (a file's modification time, read once an hour and carried on with
                              computer.uptime), so they keep counting across restarts; computer.uptime when
                              the file can't be written (c.real = false)
  state.load(path) -> table   {} when there's none or it can't be read
  state.save(path, t)         writes it (to path .. ".tmp", then renamed, so a crash can't leave half a file)
]]

local serialization = require("serialization")

local state = {}

local Clock = {}
Clock.__index = Clock

function state.clock(filesystem, computer, path)
  return setmetatable({ fs = filesystem, computer = computer, path = path, real = false }, Clock)
end

function Clock:sync()
  local up = self.computer.uptime()
  local f = io.open(self.path, "w")
  local ms = nil
  if f then
    f:write("lumen clock\n")
    f:close()
    local ok, v = pcall(self.fs.lastModified, self.path)
    if ok and type(v) == "number" and v > 0 then ms = v end
  end
  self.real = ms ~= nil
  self.base, self.at = ms and ms / 1000 or up, up
end

function Clock:now()
  local up = self.computer.uptime()
  if not self.at or up - self.at >= 3600 or up < self.at then self:sync() end
  return self.base + (up - self.at)
end

function state.load(path)
  local f = io.open(path, "r")
  if not f then return {} end
  local text = f:read("*a")
  f:close()
  local t = serialization.unserialize(text)
  return type(t) == "table" and t or {}
end

function state.save(path, t)
  local f = io.open(path .. ".tmp", "w")
  if not f then return false end
  f:write(serialization.serialize(t))
  f:close()
  os.remove(path)
  return os.rename(path .. ".tmp", path)
end

return state
