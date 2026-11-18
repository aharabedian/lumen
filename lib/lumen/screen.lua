--[[ lumen.screen: LUMEN's screen. Draws a model; knows nothing about the game.

  local s = require("lumen.screen").new(gpu, w, h)
  s:draw(model, actions)   build the frame and send the GPU only what changed since the last draw
  s:tap(x, y) -> bool      run the touch target under (x, y)
  s:activate()             make this screen's resolution the GPU's and repaint from scratch (big mode and back)
  s:restore()              plain terminal colors again (on exit)

  model = {
    now, version, health = "ok" | "warn" | "bad", missingConfig = bool, lens = "port 4243 as lumen" | nil,
    page = "main" | "lsc" | "group" | "energy" | "timeline" | "supplies",
    total = reading | nil,           power.total: shown first, full width, when there are several LSCs
    lscs = { reading... },           lumen.power readings, each with history = { fill (0..1)... }, oldest first,
                                     and drainHow (lumen.alerts.drain's how: "standby"...)
    switches = lumen.control c.list, sources = lumen.sources list, groups = lumen.control c.groups,
    supplies = lumen.supplies readings with rate, rate24, lasts, chart (lumen.pages.supplies),
    hours = { [switch] = seconds on in the last 24 h }, view = "tiles" | "rows" | nil,
    alerts = { { id, level, text, since }... },
    detail = (page "lsc") see lumen.pages.detail,
    group = (page "group") the group shown (lumen.pages.group),
    energy = (page "energy") lumen.energy.day's (lumen.pages.energy), time (the clock's now),
    timeline = (page "timeline") lumen.timeline.build's, with offset (lumen.pages.timeline),
    glance = bool: big mode (lumen.pages.glance, nothing else)
  }
  actions = { quit(), open(address), back(), range(k), mode(switch name, "auto" | "on" | "off"), reset(switch name),
    group(name) (its page), energy(), timeline(), supplies() (their pages), tlRange(k), tlFilter(id), tlOlder(), tlNewer(),
    view("tiles" | "rows"), glance() (BIG: big mode now; no button without it), wake() }

  A header (health, the total's fill and net, QUIT), then the page: lumen.pages.main or lumen.pages.detail.
]]

local Gui = require("lumen.gui")
local frame = require("lumen.frame")
local mainPage = require("lumen.pages.main")
local detailPage = require("lumen.pages.detail")
local groupPage = require("lumen.pages.group")
local glancePage = require("lumen.pages.glance")
local energyPage = require("lumen.pages.energy")
local timelinePage = require("lumen.pages.timeline")
local suppliesPage = require("lumen.pages.supplies")

local screen = {}

local C = Gui.C
local HEALTH_COLOR = { ok = C.good, warn = C.warn, bad = C.bad }
local HEALTH_TEXT = { ok = "OK", warn = "WARN", bad = "BAD" }
local signed = frame.signed
screen.si = frame.si

local function header(f, m, actions)
  f:rowBg(1, C.panel)
  f:text(2, 1, "LUMEN", C.accent, C.panel)
  local hc = HEALTH_COLOR[m.health] or C.dim
  f:text(9, 1, " " .. (HEALTH_TEXT[m.health] or "?") .. " ", C.bg, hc)
  local n = #m.lscs
  local summary = ("%d LSC%s"):format(n, n == 1 and "" or "s")
  local main = m.total or m.lscs[1]
  if main and main.ok and main.fill then
    summary = summary .. ("   %.1f%% full   net %s EU/t"):format(main.fill * 100, signed(main.net))
  end
  local qx = f.w - 6
  local bx = actions.glance and qx - 6 or qx
  local right = ("%sv%s"):format(m.lens and ("LENS " .. m.lens .. " · ") or "", m.version or "?")
  if 18 + Gui.len(summary) + 2 > bx - Gui.len(right) - 2 then right = "v" .. (m.version or "?") end
  local rx = bx - Gui.len(right) - 2
  f:text(18, 1, Gui.fit(summary, math.max(0, rx - 19)), C.text, C.panel)
  f:text(rx, 1, right, C.dim, C.panel)
  if actions.glance then
    f:text(bx, 1, " BIG ", C.text, C.line)
    f:hit(bx, 1, bx + 4, 1, actions.glance)
  end
  f:text(qx, 1, " QUIT ", C.text, C.line)
  f:hit(qx, 1, qx + 5, 1, actions.quit)
end

---------------------------------------------------------------- drawing
local S = {}
S.__index = S

function screen.new(gpu, w, h)
  local ui = Gui.new(gpu, w, h)
  return setmetatable({ ui = ui, w = w, h = h, last = {}, hits = {} }, S)
end

function S:build(m, actions)
  local f = frame.new(self.w, self.h)
  f.now = m.now
  if m.glance then glancePage.build(f, m, actions); return f end
  header(f, m, actions)
  if m.page == "lsc" and m.detail then detailPage.build(f, m, actions)
  elseif m.page == "group" and m.group then groupPage.build(f, m, actions)
  elseif m.page == "energy" and m.energy then energyPage.build(f, m, actions)
  elseif m.page == "supplies" then suppliesPage.build(f, m, actions)
  elseif m.page == "timeline" and m.timeline then
    timelinePage.build(f, m, { back = actions.back, range = actions.tlRange, filter = actions.tlFilter,
      older = actions.tlOlder, newer = actions.tlNewer })
  else mainPage.build(f, m, actions) end
  local foot = m.missingConfig and "No /home/lumen.cfg: defaults (see config/lumen.example.cfg)."
    or (m.page == "lsc" and "Tap a range for a longer history.")
    or (m.page == "group" and "Change the steps in lumen-setup: GROUPS.")
    or (m.page == "energy" and "The last 24 hours, kept across restarts. Sources come and go with lumen-setup.")
    or (m.page == "timeline" and "Kept 7 days in /home/lumen-log.cfg, across restarts.")
    or (m.page == "supplies" and "LUMEN only counts them; it never moves anything. Add them in lumen-setup: SUPPLIES.")
    or (#(m.groups or {}) > 0 and "Tap an LSC for its history; a group for its ladder and order.")
    or "Tap an LSC for its history and the last 24 hours."
  f:text(2, self.h, Gui.fit(foot, self.w - 2), C.dim)
  return f
end

function S:draw(m, actions)
  local f = self:build(m, actions)
  frame.paint(self.ui, self.last, f)
  self.hits = f.hits
end

function S:tap(x, y) return frame.tap(self.hits, x, y) end

function S:activate()
  self.ui.gpu.setResolution(self.w, self.h)
  self.ui.fill(1, 1, self.w, self.h, C.bg)
  self.last = {}
end

function S:restore() self.ui.restore() end

return screen
