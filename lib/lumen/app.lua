--[[ lumen.app: the lumen program's state and reactions, without the event loop (src/lumen.lua has that).

  local app = require("lumen.app").new(cfg, env)
    cfg: lumen.config output. env = { component, gpu, w, h, modem?, beep?, filesystem?, computer?, statePath? }
    modem: used only when cfg.lensPort is set. statePath: lumen.state's file (nil: nothing kept between runs);
    filesystem and computer: for its clock.
  app:start(now)                     announce to LENS (if reporting), then the first reading
  app:tick(now)                      every cfg.interval seconds: read LSCs and sources, switch, history, alerts,
                                     beep, redraw, report; save state every 5 minutes
  app:onTouch(x, y, now)             tap the screen, redraw (and save at once when a switch's mode changed); in big
                                     mode a tap only wakes it
  app:senseDue() -> time | nil       when to ask the radar next (big mode: every 2 s)
  app:sense(now)                     ask them: someone arriving wakes big mode; someone near keeps it awake
  app:onModem(port, data)            a packet: answers the LENS hub's hello
  app:stop()                         saves state, closes LENS, restores the screen
  app.running, app.readings, app.total, app.sources, app.control (lumen.control), app.history (lumen.history),
  app.alerts (lumen.alerts tracker), app.screen, app.lens, app.page ("main" | "lsc" | "group"), app.lsc,
  app.range, app.group (a group's name), app.view ("tiles" | "rows" | nil: tiles when they all fit; kept),
  app.big (big mode: lumen.pages.glance at a coarser resolution, app.bigScreen), app.presence (lumen.presence)
  app.glanceSize(w, h, scale) -> w, h   big mode's resolution: w / scale (40 at least), the same shape

  Big mode: after cfg.glanceAfter seconds (0: never by itself) without a tap or anyone near (a radar is asked
  then, so someone standing there keeps it awake), or BIG. A tap wakes it, and so does someone arriving: the
  radar finding a player near who wasn't at the last look (after BIG, whoever tapped it is still there).
  app:model(now) -> what the screen draws

  Beeps once when a bad alert is raised or a warning becomes bad (cfg.beep). A LENS failure never stops the
  screen (app.lensError says why).
]]

local alerts = require("lumen.alerts")
local control = require("lumen.control")
local history = require("lumen.history")
local power = require("lumen.power")
local presence = require("lumen.presence")
local screen = require("lumen.screen")
local sources = require("lumen.sources")
local state = require("lumen.state")
local Telemetry = require("lumen.telemetry")
local VERSION = require("lumen.version")

local app = {}

local SAVE_EVERY = 300
local SENSE_BIG = 2      -- seconds between looks for someone, in big mode

function app.glanceSize(w, h, scale)
  local gw = math.min(w, math.max(40, w // scale))
  local gh = math.min(h, math.max(10, math.floor(gw * h / w + 0.5)))
  return gw, gh
end
local KEEP_HISTORY = 2 * 86400   -- history saved longer ago than this is dropped at start

local App = {}
App.__index = App

function app.new(cfg, env)
  local self = setmetatable({ cfg = cfg, env = env, running = true, readings = {}, sources = {},
    page = "main", range = 1, onTime = {} }, App)
  local saved = {}
  if env.statePath then
    self.clock = state.clock(env.filesystem, env.computer, env.statePath .. ".clock")
    saved = state.load(env.statePath)
  end
  local time = self:time()
  local fresh = self.clock and self.clock.real and type(saved.saved) == "number" and time - saved.saved < KEEP_HISTORY
  self.history = history.new(fresh and saved.history or nil)
  self.power = power.new(env.component, cfg)
  self.sourceReader = sources.new(env.component, cfg)
  self.control = control.new(env.component, cfg, saved)
  self.view = (saved.view == "tiles" or saved.view == "rows") and saved.view or nil
  self.alerts = alerts.tracker()
  self.presence = presence.new(env.component, cfg)
  self.bigScreen = screen.new(env.gpu, app.glanceSize(env.w, env.h, cfg.glanceScale or 3))
  self.screen = screen.new(env.gpu, env.w, env.h)       -- made last: its resolution is the one set
  self.big = false
  self.lens = Telemetry.open(cfg, env.modem)
  self.actions = {
    quit = function() self.running = false end,
    open = function(address) self.page, self.lsc, self.range = "lsc", address, 1 end,
    back = function() self.page = "main" end,
    group = function(name) self.page, self.group = "group", name end,
    view = function(v) self.view, self.dirty = v, true end,
    glance = function() self:goBig(self.now or 0, true) end,
    wake = function() self:wake(self.now or 0) end,
    range = function(k) self.range = k end,
    mode = function(name, mode)
      self.control:setMode(name, mode, self.now or 0)
      self.dirty = true
    end,
    reset = function(name)
      self.control:reset(name, self.now or 0)
      self.dirty = true
    end,
  }
  return self
end

function App:time()
  if self.clock then return self.clock:now() end
  return self.now or 0
end

function App:lensCall(fn, ...)
  if not self.lens then return end
  local ok, err = pcall(fn, self.lens, ...)
  self.lensError = not ok and tostring(err) or nil
end

function App:reading(address)
  if address == "" then return self.total end
  for _, r in ipairs(self.readings) do if r.address == address then return r end end
end

function App:model(now)
  local list = self.alerts.list
  if self.lensError then
    list = { table.unpack(list) }
    list[#list + 1] = { id = "lens", level = "warn", text = "LENS reporting failed: " .. self.lensError, since = now }
  end
  local m = {
    now = now, version = VERSION, health = alerts.health(list), missingConfig = self.cfg.missing,
    lens = self.lens and ("port " .. self.lens.port .. " as " .. self.cfg.lensNode) or nil,
    lscs = self.readings, total = self.total, alerts = list, page = self.page,
    switches = self.control.list, sources = self.sources, groups = self.control.groups, hours = self.onTime,
    view = self.view, glance = self.big,
  }
  if self.page == "group" then
    for _, g in ipairs(self.control.groups) do if g.name == self.group then m.group = g end end
    if not m.group then m.page = "main" end
  end
  if self.page == "lsc" then
    local time = self:time()
    local names = {}
    for _, rg in ipairs(history.RANGES) do names[#names + 1] = rg.name end
    m.detail = { reading = self:reading(self.lsc), range = self.range, ranges = names,
      chart = self.history:chart(self.lsc, self.range), day = self.history:day(self.lsc, time),
      before = self.history:day(self.lsc, time - 86400), time = time }
  end
  return m
end

function App:redraw(now) (self.big and self.bigScreen or self.screen):draw(self:model(now), self.actions) end

function App:goBig(now, byHand)
  if self.big then return end
  self.big = true
  if byHand then self.near = nil end     -- whoever tapped is near: only someone arriving later wakes it
  self.bigScreen:activate()
  self:redraw(now)
end

function App:wake(now)
  self.active = now
  if not self.big then return end
  self.big = false
  self.screen:activate()
  self:redraw(now)
end

function App:senseDue()
  if not (self.big and self.presence.polls) then return nil end
  return (self.lastSense or -math.huge) + SENSE_BIG
end

function App:sense(now)
  self.lastSense = now
  local near = self.presence:poll()
  local was = self.near
  self.near = near == true
  if not near then return end
  if not self.big then self.active = now
  elseif was == false then self:wake(now) end         -- someone arrived
end

function App:start(now)
  self.active = now
  self:lensCall(Telemetry.announce)
  self:tick(now)
end

function App:save()
  self.dirty = false
  if not self.env.statePath then return end
  local c = self.control
  pcall(state.save, self.env.statePath, { saved = self:time(), modes = c:modes(), faults = c:faults(), trips = c:trips(),
    groups = c:groupSteps(), view = self.view, history = self.history:save() })
end

function App:tick(now)
  local dt = self.now and math.min(now - self.now, 3 * self.cfg.interval) or 0
  self.now = now
  local time = self:time()
  self.readings = self.power:read()
  self.total = power.total(self.readings)
  self.sources = self.sourceReader:read()
  self.onTime = self.history:day("", time).on
  self.control:update(self.readings, self.total, now, { sources = self.sources, onTime = self.onTime })
  local latched = {}
  for name in pairs(self.control:faults()) do latched[#latched + 1] = name end
  for name, why in pairs(self.control:trips()) do
    latched[#latched + 1] = name .. ": " .. (type(why) == "table" and ("rearm " .. tostring(why.rearm)) or why)
  end
  table.sort(latched)
  latched = table.concat(latched, "\n")
  if latched ~= (self.latched or "") then self.latched, self.dirty = latched, true end -- kept at once, not in 5 min

  local all, keep = { table.unpack(self.readings) }, {}
  if self.total then all[#all + 1] = self.total end
  local h = self.history
  for _, r in ipairs(all) do
    keep[r.address] = true
    h:add(r.address, r, time, dt)
    r.history = h:chart(r.address, 1)
  end
  h:keep(keep)
  for _, s in ipairs(self.control.list) do h:switch(s.name, s.on, time, dt) end

  local ctx = { now = now, switches = self.control.list, sources = self.sources,
    rate = function(address, seconds) return h:rate(address, seconds, time) end }
  for _, r in ipairs(all) do
    if r.ok then r.drainSeconds, r.drainHow = alerts.drain(r, self.cfg, ctx) end
  end
  local new = self.alerts:update(alerts.evaluate(self.readings, self.cfg, ctx), now)
  if self.cfg.beep and self.env.beep then
    local bad = false
    for _, a in ipairs(self.alerts.list) do
      for _, id in ipairs(new) do if a.id == id and a.level == "bad" then bad = true end end
    end
    if bad then self.env.beep() end
  end
  self:lensCall(Telemetry.report, self.readings, self.alerts.list, { total = self.total, sources = self.sources,
    switches = self.control.list, groups = self.control.groups, history = h, time = time })
  local after = self.cfg.glanceAfter or 0
  if not self.big and after > 0 and now - (self.active or now) >= after then
    if self.presence.polls then self:sense(now) end    -- someone standing there keeps it awake
    if now - self.active >= after then self:goBig(now) end
  end
  self.nextSave = self.nextSave or now + SAVE_EVERY
  if self.dirty or now >= self.nextSave then
    self:save()
    self.nextSave = now + SAVE_EVERY
  end
  self:redraw(now)
end

function App:onTouch(x, y, now)
  if self.big then self:wake(now); return end      -- a tap in big mode only wakes it
  self.active = now
  self.screen:tap(x, y)
  if self.dirty then self:save() end
  if self.running then self:redraw(now) end
end

function App:onModem(port, data)
  if self.lens and port == self.lens.port and type(data) == "string" then self:lensCall(Telemetry.handle, data) end
end

function App:stop()
  self:save()
  if self.lens then pcall(Telemetry.close, self.lens) end
  self.screen:restore()
end

return app
