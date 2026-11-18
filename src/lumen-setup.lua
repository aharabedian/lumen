--[[ lumen-setup.lua - set LUMEN up: writes /home/lumen.cfg (and /home/.shrc).

  Usage: lumen-setup [--text]

  With a GPU and screen of 80x25 or more (tier 2 and up), a touchscreen editor: tabs for LSCs, power sources,
  switches and general settings (alerts, LENS, start on boot). Switches have COPY, which makes the next one
  from the one selected (the next redstone block, the next name), for a row of reactors. SAVE shows what
  changes before writing. TEXT SETUP (or --text) asks the questions on the terminal instead: names the LSCs it
  finds, offers generators and reactors as power sources, sets up switches, the alerts, LENS and starting on
  boot, and shows the file before saving it.

  Either way the old file is kept as lumen.cfg.bak, and settings it doesn't show are kept. In the text setup,
  current settings are the defaults (Enter keeps one) and Ctrl+D cancels. The work is in /home/lib/lumen/setup/.
]]

if not package.path:find("/home/lib/?.lua", 1, true) then package.path = package.path .. ";/home/lib/?.lua" end
for name in pairs(package.loaded) do if name:find("^lumen%.") then package.loaded[name] = nil end end
if not pcall(require, "lumen.version") then error("LUMEN's modules are missing from /home/lib/lumen - run lumen-update", 0) end

local component = require("component")
local VERSION   = require("lumen.version")
local input     = require("lumen.setup.input")

local home = (os.getenv("LUMEN_PREFIX") or "") .. "/home"
local env = { component = component, event = require("event"), cfgPath = home .. "/lumen.cfg", shrcPath = home .. "/.shrc" }

local function main(...)
  if ({ ... })[1] ~= "--text" then
    local screen = require("lumen.setup.screen")
    local ok, why = screen.available(component)
    if ok then
      if screen.run(env) ~= "text" then return end
    else
      print("lumen-setup: " .. why .. ", so the text setup")
    end
  end
  print("lumen-setup " .. VERSION .. " - Enter keeps the [default], Ctrl+D cancels")
  require("lumen.setup.steps").run(env)
end

local ok, err = pcall(main, ...)
if not ok then
  if err == input.CANCEL then print(""); print("cancelled - nothing saved")
  else error(err, 0) end
end
