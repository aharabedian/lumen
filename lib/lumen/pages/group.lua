--[[ lumen.pages.group: one group of switches. LADDER: the fill it follows against each step's marks (how many run
  below each, and when they go back), and how many it needs now. ORDER: its members by who starts next (least
  run time in the last 24 hours, or lumen.cfg's order without rotate), each with what it's doing and why it's
  left out (a fault, a heat trip, set by hand). Side by side from 120 columns, else one above the other.
  BACK returns to the main page.

  group.build(f, m, actions)   m.group: a lumen.control group (c.groups entry); actions.back()
]]

local Gui = require("lumen.gui")
local frame = require("lumen.frame")

local group = {}

local C = frame.C
local ago = frame.ago

-- What a member is doing, for ORDER: text, colour, and why it's left out of the group (nil: it's in).
local function memberState(s)
  if s.err then return "ERROR", C.bad, s.err end
  if s.trip and s.trip.on then return "TRIP", C.bad, "skipped until RESET (" .. (s.trip.why or "heat") .. ")" end
  if s.fault and s.fault.on and s.cfg.fault.stop then
    return "FAULT", C.bad, s.fault.latched and "skipped until RESET" or "skipped while the fault lasts"
  end
  if s.mode ~= "auto" then return (s.mode == "on" and "ON" or "OFF") .. " by hand", C.info, "out of the group until AUTO" end
  if s.on == nil then return "?", C.dim end
  if s.why == "waiting to switch again" then return s.on and "ON, waiting" or "waiting", C.info end
  return s.on and "ON" or "standby", s.on and C.good or C.dim
end

local function ladder(f, g, x, top, bottom, width)
  local h = bottom - top
  local function yOf(p) return top + math.floor((100 - p) / 100 * h + 0.5) end
  for _, p in ipairs(h >= 16 and { 100, 75, 50, 25, 0 } or { 100, 50, 0 }) do
    f:text(x, yOf(p), Gui.rfit(p .. "%", 4), C.dim)
  end
  local fillY = g.fill and yOf(g.fill * 100)
  for y = top, bottom do f:text(x + 5, y, "      ", C.text, (fillY and y >= fillY) and C.good or C.line) end
  local marked, cum = {}, 0
  for k, st in ipairs(g.steps) do
    local prev = cum
    cum = cum + st.run
    local label = k == 1 and ("below %g%%: %d on, all off above %g%%"):format(st.onBelow, cum, st.offAbove)
      or ("below %g%%: %d on, back to %d above %g%%"):format(st.onBelow, cum, prev, st.offAbove)
    local y = yOf(st.onBelow)
    marked[y] = true
    f:text(x + 12, y, "── " .. Gui.fit(label, width - 15), st.active and C.text or C.dim)
  end
  if fillY then
    local y = fillY
    if marked[y] then y = (y < bottom and not marked[y + 1]) and y + 1 or y - 1 end
    local now = ("◀ %.1f%% now: %s"):format(g.fill * 100, g.need and (g.need .. " needed") or "deciding")
    f:text(x + 12, y, Gui.fit(now, width - 12), C.info)
  else
    f:text(x + 12, bottom, Gui.fit("◀ " .. (g.why or "can't read the LSC"), width - 12), C.warn)
  end
end

local function order(f, g, x, y, width, last)
  local barW = width >= 90 and 20 or 10
  local cols = { num = x, name = x + 3, now = x + 13, bar = x + 29, note = x + 29 + barW + 8 }
  f:text(cols.num, y, "#", C.dim)
  f:text(cols.name, y, "SWITCH", C.dim)
  f:text(cols.now, y, "NOW", C.dim)
  f:text(cols.bar, y, "RUN TIME, 24 H", C.dim)
  f:text(cols.note, y, "NOTE", C.dim)
  -- Who starts first and who stops first, among the members in the group.
  local firstOff, lastOn
  for _, s in ipairs(g.order) do
    local _, _, out = memberState(s)
    if not out and s.on == false and not firstOff then firstOff = s end
    if not out and s.on then lastOn = s end
  end
  local rank, row = 0, y + 1
  for i, s in ipairs(g.order) do
    if row > last then break end
    if row == last and i < #g.order then
      f:text(x, row, ("+%d more"):format(#g.order - i + 1), C.dim)
      break
    end
    local state, colour, out = memberState(s)
    if not out then rank = rank + 1 end
    local secs = g.hours and g.hours[s.name] or 0
    f:text(cols.num, row, out and "–" or tostring(rank), C.dim)
    f:text(cols.name, row, Gui.fit(s.name, 9), C.text)
    f:text(cols.now, row, Gui.fit(state, 15), colour)
    f:bar(cols.bar, row, barW, 1, secs / 86400, s.on and C.good or C.dim)
    f:text(cols.bar + barW + 1, row, ago(secs), C.text)
    local note = out
    if not note and g.rotate and s == firstOff then note = "next to start: least run time" end
    if not note and g.rotate and s == lastOn then note = "first to stop: most run time" end
    if note then f:text(cols.note, row, Gui.fit(note, math.max(0, x + width - cols.note)), out and colour or C.dim) end
    row = row + 1
  end
  return row
end

function group.build(f, m, actions)
  local g = m.group
  local width = f.w - 2
  local bx = f:button(2, 3, "◀ BACK", actions.back)
  f:text(bx, 3, g.name, C.accent)
  local about = ("group of %d · %s"):format(#g.members, g.rotate and "the least run time starts first" or "starts in lumen.cfg's order")
  f:text(bx + Gui.len(g.name) + 2, 3, Gui.fit(about, math.max(0, width - bx - Gui.len(g.name) - 30)), C.dim)
  local summary = g.need and ("%d needed · %d running"):format(g.need, g.running or 0) or (g.why or "deciding")
  f:text(f.w - Gui.len(summary), 3, summary, C.text)

  local wide = f.w >= 120
  local lastRow = f.h - 2
  if wide then
    local bottom = math.min(6 + 20, lastRow - 6)
    f:text(2, 5, "LADDER", C.accent)
    f:text(10, 5, "how many run at each fill", C.dim)
    ladder(f, g, 2, 6, bottom, 53)
    f:text(58, 5, "ORDER", C.accent)
    f:text(65, 5, "who starts next, from the top", C.dim)
    local y = order(f, g, 58, 6, f.w - 58, lastRow - 3)
    f:text(58, y + 1, Gui.fit("One more needed: the top one off starts. One fewer: the bottom one on stops. A member", f.w - 59), C.dim)
    f:text(58, y + 2, Gui.fit("left out is skipped, and each still waits a minute between its own switches.", f.w - 59), C.dim)
  else
    f:text(2, 5, "LADDER", C.accent)
    local bottom = math.min(6 + 10, lastRow - 6)
    ladder(f, g, 2, 6, bottom, width)
    f:text(2, bottom + 2, "ORDER", C.accent)
    order(f, g, 2, bottom + 3, width, lastRow)
  end
end

return group
