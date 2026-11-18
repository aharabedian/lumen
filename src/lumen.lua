--[[ lumen.lua - LUMEN: every LSC this computer reaches, on one screen: how full, what flows in and out,
  how long until full or empty, and alerts. Optionally reports to LENS.

  Needs a GPU and screen (tier 3 for the full layout; tier 2 works) and an adapter on each LSC's controller.
  Reporting to LENS also needs a network card. Settings: /home/lumen.cfg (optional; docs/configuration.md).
  Usage: lumen [path]    (default /home/lumen.cfg)
  QUIT or Ctrl+C to stop. The work is in /home/lib/lumen/.
]]

-- Modules live in /home/lib/lumen (lumen-update installs them). Forget copies cached by an earlier
-- run, so restarting after an update loads the new ones.
if not package.path:find("/home/lib/?.lua", 1, true) then package.path = package.path .. ";/home/lib/?.lua" end
for name in pairs(package.loaded) do if name:find("^lumen%.") then package.loaded[name] = nil end end
if not pcall(require, "lumen.version") then error("LUMEN's modules are missing from /home/lib/lumen - run lumen-update", 0) end

local component  = require("component")
local computer   = require("computer")
local event      = require("event")
local filesystem = require("filesystem")
local term      = require("term")
local config    = require("lumen.config")
local App       = require("lumen.app")
local Gui       = require("lumen.gui")
local splash    = require("lumen.splash")

local path = ({ ... })[1] or "/home/lumen.cfg"
local cfg, err = config.load(path)
if not cfg then error(path .. ": " .. tostring(err), 0) end

if cfg.lensPort and not component.isAvailable("modem") then
  error(path .. ": lensPort is set, but there's no network card to report to LENS with", 0)
end
local gpu = component.gpu
local w, h = Gui.size(component, cfg.resolution)
-- What LUMEN keeps between runs (switches set by hand, history) goes next to the config file.
local dir = path:match("^(.*)/[^/]*$") or "."
local statePath = dir .. "/lumen-state.cfg"
local app = App.new(cfg, { component = component, gpu = gpu, w = w, h = h,
  modem = cfg.lensPort and component.modem or nil, beep = computer.beep,
  filesystem = filesystem, computer = computer, statePath = statePath, logPath = dir .. "/lumen-log.cfg" })
splash.show(gpu, w, h, "LUMEN", require("lumen.version"), Gui.C.accent)
os.sleep(splash.SECONDS)   -- yields: OpenOS keeps running while the logo shows

local function main()
  app:start(computer.uptime())
  local nextTick = computer.uptime() + cfg.interval
  while app.running do
    local due = app:senseDue()
    local ev = table.pack(event.pullMultiple(math.max(0.05, math.min(nextTick, due or math.huge) - computer.uptime()),
      "touch", "modem_message", "interrupted"))
    local now = computer.uptime()
    if ev[1] == "touch" then
      -- touch: screenAddress, x, y, button, player
      app:onTouch(math.floor(ev[3]), math.floor(ev[4]), now, ev[6])
    elseif ev[1] == "modem_message" then
      -- modem_message: localAddress, remoteAddress, port, distance, payload
      app:onModem(ev[4], ev[6])
    elseif ev[1] == "interrupted" then
      app.running = false
    end
    due = app:senseDue()
    if app.running and due and now >= due then app:sense(now) end
    if app.running and now >= nextTick then
      app:tick(now)
      nextTick = now + cfg.interval
    end
  end
end

local ok, failure = xpcall(main, debug.traceback)
app:stop()
term.clear()
if not ok then io.stderr:write(tostring(failure) .. "\n") end
