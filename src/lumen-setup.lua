--[[ lumen-setup.lua - guided setup for LUMEN: writes /home/lumen.cfg.

  Usage: lumen-setup

  Names the LSCs it finds, offers generators and reactors as power sources, sets up switches (generators on
  when the LSCs run low, off when they're full: a redstone signal or a GT machine's work switch), the alerts,
  reporting to LENS, and starting lumen on boot (through /home/.shrc). Shows the file before saving it, and keeps
  the old one as lumen.cfg.bak.

  Run it again any time: current settings are the defaults (Enter keeps one), and settings it doesn't ask
  about are kept. Ctrl+D cancels. The steps live in /home/lib/lumen/setup/.
]]

if not package.path:find("/home/lib/?.lua", 1, true) then package.path = package.path .. ";/home/lib/?.lua" end
for name in pairs(package.loaded) do if name:find("^lumen%.") then package.loaded[name] = nil end end
if not pcall(require, "lumen.version") then error("LUMEN's modules are missing from /home/lib/lumen - run lumen-update", 0) end

local component = require("component")
local VERSION   = require("lumen.version")
local input     = require("lumen.setup.input")
local steps     = require("lumen.setup.steps")

local home = (os.getenv("LUMEN_PREFIX") or "") .. "/home"
print("lumen-setup " .. VERSION .. " - Enter keeps the [default], Ctrl+D cancels")
local ok, err = pcall(steps.run, { component = component, cfgPath = home .. "/lumen.cfg", shrcPath = home .. "/.shrc" })
if not ok then
  if err == input.CANCEL then print(""); print("cancelled - nothing saved")
  else error(err, 0) end
end
