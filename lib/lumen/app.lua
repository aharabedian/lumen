--[[ lumen.app: the lumen program's state and reactions, without the event loop (src/lumen.lua has that).

  local app = require("lumen.app").new(cfg, { component, gpu, w, h, modem?, beep? })
    cfg: lumen.config output. modem: used only when cfg.lensPort is set.
  app:start(now)                     announce to LENS (if reporting), then the first reading
  app:tick(now)                      every cfg.interval seconds: read the LSCs, alerts, beep, redraw, report
  app:onTouch(x, y, now)             tap the screen, redraw
  app:onModem(port, data)            a packet: answers the LENS hub's hello
  app:stop()
  app.running, app.readings, app.total (power.total), app.alerts (lumen.alerts tracker), app.screen (lumen.screen), app.lens
  app:model(now) -> what the screen draws

  Beeps once when a bad alert appears or a warn becomes bad (cfg.beep). Keeps a fill sample per LSC (and the
  total) every 30 s, the last 160 (80 minutes), for the screen's chart. A LENS failure never stops the screen (app.lensError says why).
]]

local alerts = require("lumen.alerts")
local power = require("lumen.power")
local screen = require("lumen.screen")
local Telemetry = require("lumen.telemetry")
local VERSION = require("lumen.version")

local app = {}

local HISTORY = 160   -- fill samples kept per LSC, one every SAMPLE seconds: 80 minutes
local SAMPLE = 30

local App = {}
App.__index = App

function app.new(cfg, env)
  local self = setmetatable({ cfg = cfg, env = env, running = true, readings = {}, history = {} }, App)
  self.power = power.new(env.component, cfg)
  self.alerts = alerts.tracker()
  self.screen = screen.new(env.gpu, env.w, env.h)
  self.lens = Telemetry.open(cfg, env.modem)
  self.actions = { quit = function() self.running = false end }
  return self
end

function App:lensCall(fn, ...)
  if not self.lens then return end
  local ok, err = pcall(fn, self.lens, ...)
  self.lensError = not ok and tostring(err) or nil
end

function App:model(now)
  local list = self.alerts.list
  if self.lensError then
    list = { table.unpack(list) }
    list[#list + 1] = { id = "lens", level = "warn", text = "LENS reporting failed: " .. self.lensError, since = now }
  end
  return {
    now = now, version = VERSION, health = alerts.health(list), missingConfig = self.cfg.missing,
    lens = self.lens and ("port " .. self.lens.port .. " as " .. self.cfg.lensNode) or nil,
    lscs = self.readings, total = self.total, alerts = list,
  }
end

function App:redraw(now) self.screen:draw(self:model(now), self.actions) end

function App:start(now)
  self:lensCall(Telemetry.announce)
  self:tick(now)
end

function App:tick(now)
  self.readings = self.power:read()
  local seen, sample = {}, now >= (self.nextSample or 0)
  self.total = power.total(self.readings)
  local all = { table.unpack(self.readings) }
  all[#all + 1] = self.total
  for _, r in ipairs(all) do
    seen[r.address] = true
    local h = self.history[r.address] or {}
    self.history[r.address] = h
    if r.ok and sample then
      h[#h + 1] = r.fill or 0
      if #h > HISTORY then table.remove(h, 1) end
    end
    r.history = h
  end
  if sample then self.nextSample = now + SAMPLE end
  for address in pairs(self.history) do if not seen[address] then self.history[address] = nil end end
  local list = alerts.evaluate(self.readings, self.cfg)
  local new = self.alerts:update(list, now)
  if self.cfg.beep and self.env.beep then
    local bad = false
    for _, a in ipairs(list) do
      for _, id in ipairs(new) do if a.id == id and a.level == "bad" then bad = true end end
    end
    if bad then self.env.beep() end
  end
  self:lensCall(Telemetry.report, self.readings, list)
  self:redraw(now)
end

function App:onTouch(x, y, now)
  self.screen:tap(x, y)
  if self.running then self:redraw(now) end
end

function App:onModem(port, data)
  if self.lens and port == self.lens.port and type(data) == "string" then self:lensCall(Telemetry.handle, data) end
end

function App:stop()
  if self.lens then pcall(Telemetry.close, self.lens) end
  self.screen:restore()
end

return app
