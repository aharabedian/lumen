--[[ lumen.screen: LUMEN's screen. Draws a model; knows nothing about the game.

  local s = require("lumen.screen").new(gpu, w, h)
  s:draw(model, actions)   build the frame and send the GPU only what changed since the last draw
  s:tap(x, y) -> bool      run the touch target under (x, y)
  s:restore()              plain terminal colors again (on exit)

  model = {
    now, version, health = "ok" | "warn" | "bad", missingConfig = bool, lens = "port 4243 as lumen" | nil,
    total = reading | nil,           power.total: shown first, full width, when there are several LSCs
    lscs = { reading... },           lumen.power readings, each with history = { fill (0..1)... }, oldest first
    alerts = { { id, level, text, since }... },
  }
  actions = { quit() }

  Layout: a header, a panel per LSC (the total first), alerts at the bottom. Panels grow with the room they
  get: a name and figures line, a fill bar (up to six rows tall when there's room), flows (5 s averages), longer
  averages, and a chart of the fill history in the rows left over. With 120 columns or more, several LSCs sit in two columns. Panels that
  don't fit end with "+N more"; so do alerts.
]]

local Gui = require("lumen.gui")
local power = require("lumen.power")

local screen = {}

local C = Gui.C
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local HEALTH_COLOR = { ok = C.good, warn = C.warn, bad = C.bad }
local HEALTH_TEXT = { ok = "OK", warn = "WARN", bad = "BAD" }

---------------------------------------------------------------- formatting
local function si(v, digits)
  if v == nil then return "–" end
  local a = math.abs(v)
  for _, u in ipairs({ { 1e18, "E" }, { 1e15, "P" }, { 1e12, "T" }, { 1e9, "G" }, { 1e6, "M" }, { 1e3, "k" } }) do
    if a >= u[1] then return (("%." .. (digits or 2) .. "f"):format(v / u[1])) .. u[2] end
  end
  return tostring(math.floor(v + 0.5))
end
screen.si = si

local function signed(v)
  if v == nil then return "–" end
  if v > 0 then return "+" .. si(v) end
  return si(v)
end

local function ago(s)
  s = math.max(0, math.floor(s or 0))
  if s < 60 then return s .. "s" end
  if s < 3600 then return (s // 60) .. "m" end
  return ("%dh%02dm"):format(s // 3600, (s % 3600) // 60)
end

---------------------------------------------------------------- frame building
local Frame = {}
Frame.__index = Frame

local function newFrame(w, h)
  local rows = {}
  for y = 1, h do rows[y] = { bg = C.bg, segs = {} } end
  return setmetatable({ w = w, h = h, rows = rows, hits = {} }, Frame)
end

function Frame:text(x, y, s, fg, bg)
  if y < 1 or y > self.h or x > self.w or x < 1 then return end
  local room = self.w - x + 1
  if Gui.len(s) > room then s = Gui.fit(s, room) end
  local segs = self.rows[y].segs
  segs[#segs + 1] = { x, s, fg or C.text, bg or self.rows[y].bg }
end

function Frame:rowBg(y, bg) if self.rows[y] then self.rows[y].bg = bg end end
function Frame:hit(x1, y1, x2, y2, fn) self.hits[#self.hits + 1] = { x1, y1, x2, y2, fn } end

local function rowKey(row)
  local parts = { row.bg }
  for _, s in ipairs(row.segs) do parts[#parts + 1] = s[1] .. "\1" .. s[2] .. "\1" .. s[3] .. "\1" .. s[4] end
  return table.concat(parts, "\2")
end

---------------------------------------------------------------- sections
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
  f:text(18, 1, summary, C.text, C.panel)
  local right = ("%sv%s"):format(m.lens and ("LENS " .. m.lens .. " · ") or "", m.version or "?")
  local qx = f.w - 6
  f:text(qx - Gui.len(right) - 2, 1, right, C.dim, C.panel)
  f:text(qx, 1, " QUIT ", C.text, C.line)
  f:hit(qx, 1, qx + 5, 1, actions.quit)
end

local function levelOf(r, alerts)
  local level
  for _, a in ipairs(alerts or {}) do
    if r.address ~= "" and a.id:sub(-#r.address - 1) == ":" .. r.address then
      if a.level == "bad" then return "bad" end
      level = "warn"
    end
  end
  return level
end

-- Fill history as a chart `rows` tall, newest on the right, 0 at the bottom and full at the top: one
-- column per sample, eighth-blocks for the part of a row.
local function chart(f, history, x, y, width, rows)
  local n = #history
  local first = math.max(1, n - width + 1)
  for k = rows - 1, 0, -1 do
    local out = {}
    for i = first, n do
      local level = math.max(0, math.min(1, history[i] or 0)) * rows * 8 - k * 8
      level = math.floor(math.max(0, math.min(8, level)) + 0.5)
      out[#out + 1] = level == 0 and " " or SPARK[level]
    end
    f:text(x, y + (rows - 1 - k), table.concat(out), C.info)
  end
end

local function etaText(r)
  if r.full then return "full in " .. power.duration(r.full), C.good end
  if r.empty then return "empty in " .. power.duration(r.empty), C.warn end
  if r.fill and r.fill >= 0.9995 then return "full", C.good end
  return "steady", C.dim
end

-- A panel in rows y .. y + h - 1: name and figures, the fill bar (taller from h = 6), flows, longer
-- averages, then the fill history chart in the rows left, as far as h allows.
local function panel(f, r, x, y, width, h, level)
  local color = level == "bad" and C.bad or level == "warn" and C.warn or C.text
  if not r.ok then
    f:text(x, y, Gui.fit(r.name, width), C.accent)
    f:text(x, y + 1, Gui.fit("can't be read: " .. tostring(r.err), width), C.bad)
    return
  end
  local pct = r.fill and ("%.1f%%"):format(r.fill * 100) or "–"
  local figures = ("%s / %s EU  "):format(si(r.stored), si(r.capacity))
  f:text(x, y, Gui.fit(r.name, width - Gui.len(figures) - Gui.len(pct)), C.accent)
  f:text(x + width - Gui.len(figures) - Gui.len(pct), y, figures, C.dim)
  f:text(x + width - Gui.len(pct), y, pct, color)
  local barRows = h >= 6 and math.min(6, h - 4) or 1
  local last = y + h - 1
  local barColor = level == "bad" and C.bad or level == "warn" and C.warn or C.good
  local filled = math.floor(math.max(0, math.min(1, r.fill or 0)) * width + 0.5)
  for by = y + 1, y + barRows do
    if filled > 0 then f:text(x, by, string.rep(" ", filled), C.text, barColor) end
    if filled < width then f:text(x + filled, by, string.rep(" ", width - filled), C.text, C.line) end
  end
  local row = y + barRows + 1
  if row <= last then
    local flows = ("in %s   out %s   net %s EU/t"):format(si(r.inEut), si(r.outEut), signed(r.net))
    local eta, etaColor = etaText(r)
    f:text(x, row, Gui.fit(flows, width - Gui.len(eta) - 1), C.text)
    f:text(x + width - Gui.len(eta), row, eta, etaColor)
    row = row + 1
  end
  if row <= last then
    local more = ("net 5 min %s   1 h %s EU/t"):format(signed(r.net5m), signed(r.net1h))
    local maint = r.maintenance == "ok" and "maintenance ok" or ("maintenance: " .. tostring(r.maintenance or "?"))
    if r.passiveLoss then maint = ("loss %s EU/t   "):format(si(r.passiveLoss)) .. maint end
    f:text(x, row, Gui.fit(more, width - Gui.len(maint) - 1), C.dim)
    f:text(x + width - Gui.len(maint), row, maint, r.maintenance == "ok" and C.dim or C.warn)
    row = row + 1
  end
  if row <= last and r.history and #r.history > 0 then chart(f, r.history, x, row, width, last - row + 1) end
end

local function alertsSection(f, m, x, y, width, lastRow)
  local list = m.alerts or {}
  f:text(x, y, Gui.fit(("ALERTS (%d)"):format(#list), width), C.accent)
  y = y + 1
  if #list == 0 then
    f:text(x, y, "All good.", C.dim)
    return
  end
  local room = lastRow - y + 1
  local shown = math.min(#list, room)
  if shown < #list then shown = room - 1 end
  for i = 1, shown do
    local a = list[i]
    f:text(x, y, Gui.fit(a.level == "bad" and " BAD" or " WARN", 6), C.bg, a.level == "bad" and C.bad or C.warn)
    f:text(x + 7, y, Gui.fit(a.text, width - 7 - 7), C.text)
    f:text(x + width - 6, y, Gui.rfit(ago(m.now - (a.since or m.now)), 6), C.dim)
    y = y + 1
  end
  if shown < #list then f:text(x, y, ("+%d more"):format(#list - shown), C.dim) end
end

---------------------------------------------------------------- drawing
local S = {}
S.__index = S

function screen.new(gpu, w, h)
  local ui = Gui.new(gpu, w, h)
  return setmetatable({ ui = ui, w = w, h = h, last = {}, hits = {} }, S)
end

function S:build(m, actions)
  local f = newFrame(self.w, self.h)
  header(f, m, actions)
  local width = self.w - 2
  local nAlerts = #(m.alerts or {})
  local alertRows = math.max(2, math.min(nAlerts + 1, math.max(2, self.h // 4)))
  local alertTop = self.h - alertRows
  local top, bottom = 3, alertTop - 2       -- panels go in rows top..bottom

  if #m.lscs == 0 then
    f:text(2, top, Gui.fit("No LSC found. Put an adapter next to an LSC's controller block,", width), C.dim)
    f:text(2, top + 1, Gui.fit("touching this computer or connected to it with cable.", width), C.dim)
  else
    local cols = (self.w >= 120 and #m.lscs >= 2) and 2 or 1
    local gridRows = (#m.lscs + cols - 1) // cols + (m.total and 1 or 0)
    local h = math.max(2, math.min(40, (bottom - top + 2) // gridRows - 1))
    local y = top
    if m.total then
      panel(f, m.total, 2, y, width, h, levelOf(m.total, m.alerts))
      y = y + h + 1
    end
    local pw = (width - (cols - 1) * 3) // cols
    for i, r in ipairs(m.lscs) do
      local col = (i - 1) % cols
      local py = y + ((i - 1) // cols) * (h + 1)
      if py + h - 1 > bottom then
        f:text(2, bottom + 1, ("+%d more LSCs"):format(#m.lscs - i + 1), C.dim)
        break
      end
      panel(f, r, 2 + col * (pw + 3), py, pw, h, levelOf(r, m.alerts))
    end
  end

  alertsSection(f, m, 2, alertTop, width, self.h - 1)
  local foot = m.missingConfig and "No /home/lumen.cfg: defaults (see config/lumen.example.cfg)."
    or "Every LSC this computer reaches is shown."
  f:text(2, self.h, Gui.fit(foot, width), C.dim)
  return f
end

-- Same background and the same segments at the same places with the same widths: only texts or colors
-- changed, so those segments can be redrawn in place.
local function sameShape(a, b)
  if not a or a.bg ~= b.bg or #a.segs ~= #b.segs then return false end
  for i, sa in ipairs(a.segs) do
    local sb = b.segs[i]
    if sa[1] ~= sb[1] or Gui.len(sa[2]) ~= Gui.len(sb[2]) then return false end
  end
  return true
end

function S:draw(m, actions)
  local f = self:build(m, actions)
  local ui = self.ui
  for y = 1, self.h do
    local row = f.rows[y]
    local key = rowKey(row)
    local last = self.last[y]
    if not last or last.key ~= key then
      if sameShape(last and last.row, row) then
        for i, sg in ipairs(row.segs) do
          local old = last.row.segs[i]
          if old[2] ~= sg[2] or old[3] ~= sg[3] or old[4] ~= sg[4] then ui.put(sg[1], y, sg[2], sg[3], sg[4]) end
        end
      else
        ui.fill(1, y, self.w, 1, row.bg)
        for _, sg in ipairs(row.segs) do ui.put(sg[1], y, sg[2], sg[3], sg[4]) end
      end
      self.last[y] = { key = key, row = row }
    end
  end
  self.hits = f.hits
end

function S:tap(x, y)
  for i = #self.hits, 1, -1 do
    local h = self.hits[i]
    if x >= h[1] and x <= h[3] and y >= h[2] and y <= h[4] then
      if h[5] then h[5]() end
      return true
    end
  end
  return false
end

function S:restore() self.ui.restore() end

return screen
