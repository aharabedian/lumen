--[[ lumen.screen: LUMEN's screen. Draws a model; knows nothing about the game.

  local s = require("lumen.screen").new(gpu, w, h)
  s:draw(model, actions)   build the frame and send the GPU only what changed since the last draw
  s:tap(x, y) -> bool      run the touch target under (x, y)
  s:restore()              plain terminal colors again (on exit)

  model = {
    now, version, health = "ok" | "warn" | "bad", missingConfig = bool, lens = "port 4243 as lumen" | nil,
    page = "main" | "lsc",
    total = reading | nil,           power.total: shown first, full width, when there are several LSCs
    lscs = { reading... },           lumen.power readings, each with history = { fill (0..1)... }, oldest first,
                                     and drainHow (lumen.alerts.drain's how: "standby"...)
    switches = lumen.control c.list, sources = lumen.sources list,
    alerts = { { id, level, text, since }... },
    detail = (page "lsc") see lumen.pages.detail,
  }
  actions = { quit(), open(address), back(), range(k), mode(switch name, "auto" | "on" | "off") }

  A header (health, the total's fill and net, QUIT), then the page: lumen.pages.main or lumen.pages.detail.
]]

local Gui = require("lumen.gui")
local frame = require("lumen.frame")
local mainPage = require("lumen.pages.main")
local detailPage = require("lumen.pages.detail")

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
  local right = ("%sv%s"):format(m.lens and ("LENS " .. m.lens .. " · ") or "", m.version or "?")
  if 18 + Gui.len(summary) + 2 > qx - Gui.len(right) - 2 then right = "v" .. (m.version or "?") end
  local rx = qx - Gui.len(right) - 2
  f:text(18, 1, Gui.fit(summary, math.max(0, rx - 19)), C.text, C.panel)
  f:text(rx, 1, right, C.dim, C.panel)
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
  header(f, m, actions)
  if m.page == "lsc" and m.detail then detailPage.build(f, m, actions) else mainPage.build(f, m, actions) end
  local foot = m.missingConfig and "No /home/lumen.cfg: defaults (see config/lumen.example.cfg)."
    or (m.page == "lsc" and "Tap a range for a longer history." or "Tap an LSC for its history and the last 24 hours.")
  f:text(2, self.h, Gui.fit(foot, self.w - 2), C.dim)
  return f
end

function S:draw(m, actions)
  local f = self:build(m, actions)
  frame.paint(self.ui, self.last, f)
  self.hits = f.hits
end

function S:tap(x, y) return frame.tap(self.hits, x, y) end

function S:restore() self.ui.restore() end

return screen
