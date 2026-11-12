--[[ lumen.pages.main: the main page. A panel per LSC (the total first; tap one for its page), the switches and
  sources ("POWER"), then alerts.

  main.build(f, m, actions)   f: lumen.frame; m, actions: lumen.screen's model and actions
  main.alerts(f, m, x, y, width, lastRow)   the alerts list (the detail page shows it too)

  Panels grow with the room they get: a name and figures line, a fill bar (up to six rows tall), flows (5 s
  averages), longer averages, and the fill history in the rows left. With 120 columns or more, several LSCs sit
  in two columns. Panels that don't fit end with "+N more"; so do alerts.
]]

local Gui = require("lumen.gui")
local power = require("lumen.power")
local frame = require("lumen.frame")

local main = {}

local C = frame.C
local si, signed, ago = frame.si, frame.signed, frame.ago

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

local function etaText(r)
  if r.full then return "full in " .. power.duration(r.full), C.good end
  if r.drainHow == "standby" and r.empty then return "standby, empty in " .. power.duration(r.empty), C.dim end
  if r.empty then return "empty in " .. power.duration(r.empty), C.warn end
  if r.fill and r.fill >= 0.9995 then return "full", C.good end
  return "steady", C.dim
end
main.etaText = etaText

local function panel(f, r, x, y, width, h, level, open)
  local color = level == "bad" and C.bad or level == "warn" and C.warn or C.text
  if open then f:hit(x, y, x + width - 1, y + h - 1, open) end
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
  f:bar(x, y + 1, width, barRows, r.fill, level == "bad" and C.bad or level == "warn" and C.warn or C.good)
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
  if row <= last and r.history and #r.history > 0 then f:chart(x, row, width, last - row + 1, r.history) end
end

---------------------------------------------------------------- POWER: switches and sources
local function switchRow(f, s, x, y, width, actions)
  local dot = s.err and C.bad or (s.on and C.good) or C.dim
  f:text(x, y, "●", dot)
  f:text(x + 2, y, Gui.fit(s.name, 16), C.text)
  local state = s.err and "ERROR" or (s.on == nil and "?" or (s.on and "ON" or "OFF"))
  f:text(x + 19, y, Gui.fit(state, 5), dot)
  local bx = x + width - 18
  local detail
  if s.err then detail = s.err
  else
    if s.mode == "auto" then
      detail = ("auto: on below %g%%, off above %g%%"):format(s.onBelow, s.offAbove)
      if s.why and (s.why:find("^holding") or s.why:find("^waiting")) then detail = detail .. "   " .. s.why end
    else
      detail = "by hand: " .. (s.why or "")
    end
    if s.since and f.now then detail = detail .. "   for " .. ago(f.now - s.since) end
  end
  f:text(x + 25, y, Gui.fit(detail, math.max(0, bx - x - 26)), s.err and C.bad or C.dim)
  bx = f:button(bx, y, "AUTO", function() actions.mode(s.name, "auto") end, s.mode == "auto")
  bx = f:button(bx - 1, y, "ON", function() actions.mode(s.name, "on") end, s.mode == "on")
  f:button(bx - 1, y, "OFF", function() actions.mode(s.name, "off") end, s.mode == "off")
end

local function sourceRow(f, src, x, y, width)
  local dot = not src.ok and C.bad or (src.active and C.good) or C.dim
  f:text(x, y, "●", dot)
  f:text(x + 2, y, Gui.fit(src.name, 16), C.text)
  if not src.ok then
    f:text(x + 19, y, Gui.fit("can't be read: " .. tostring(src.err), width - 19), C.bad)
    return
  end
  f:text(x + 19, y, Gui.fit(src.active and "running" or "idle", 9), dot)
  local parts = {}
  if src.output then parts[#parts + 1] = si(src.output) .. " EU/t" end
  if src.heat then parts[#parts + 1] = ("heat %.0f%%"):format(src.heat * 100) end
  if src.progress then parts[#parts + 1] = ("recipe %.0f%%"):format(src.progress * 100) end
  if src.problems and src.problems > 0 then parts[#parts + 1] = src.problems .. " maintenance problems" end
  f:text(x + 29, y, Gui.fit(table.concat(parts, "   "), width - 29), C.dim)
end

local function powerSection(f, m, x, y, width, actions, last)
  f:text(x, y, "POWER", C.accent)
  local rows = {}
  for _, s in ipairs(m.switches or {}) do rows[#rows + 1] = function(ry) switchRow(f, s, x, ry, width, actions) end end
  for _, src in ipairs(m.sources or {}) do rows[#rows + 1] = function(ry) sourceRow(f, src, x, ry, width) end end
  local room = last - y
  for i, draw in ipairs(rows) do
    if i == room and #rows > room then
      f:text(x, y + i, ("+%d more"):format(#rows - room + 1), C.dim)
      break
    end
    draw(y + i)
  end
end

function main.alerts(f, m, x, y, width, lastRow)
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

function main.build(f, m, actions)
  local width = f.w - 2
  local nAlerts = #(m.alerts or {})
  local alertRows = math.max(2, math.min(nAlerts + 1, math.max(2, f.h // 4)))
  local alertTop = f.h - alertRows
  local powerRows = #(m.switches or {}) + #(m.sources or {})
  if powerRows > 0 then powerRows = math.min(powerRows + 1, math.max(2, f.h // 4)) end
  local powerTop = alertTop - powerRows - (powerRows > 0 and 1 or 0)
  local top, bottom = 3, powerTop - 2       -- panels go in rows top..bottom

  if #m.lscs == 0 then
    f:text(2, top, Gui.fit("No LSC found. Put an adapter next to an LSC's controller block,", width), C.dim)
    f:text(2, top + 1, Gui.fit("touching this computer or connected to it with cable.", width), C.dim)
  else
    local cols = (f.w >= 120 and #m.lscs >= 2) and 2 or 1
    local gridRows = (#m.lscs + cols - 1) // cols + (m.total and 1 or 0)
    local h = math.max(2, math.min(40, (bottom - top + 2) // gridRows - 1))
    local y = top
    if m.total then
      panel(f, m.total, 2, y, width, h, levelOf(m.total, m.alerts), function() actions.open("") end)
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
      panel(f, r, 2 + col * (pw + 3), py, pw, h, levelOf(r, m.alerts), function() actions.open(r.address) end)
    end
  end

  if powerRows > 0 then powerSection(f, m, 2, powerTop, width, actions, powerTop + powerRows - 1) end
  main.alerts(f, m, 2, alertTop, width, f.h - 1)
end

return main
