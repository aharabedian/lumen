--[[ lumen.pages.group: one group of switches. LADDER: the fill on a bar with each step's mark under it, then a
  table of the steps (on below, off above, how many run in all, on or off now) and why that many are needed now.
  ORDER: its members by run time in the last 24 hours (lumen.cfg's order without rotate): who starts next (the
  first standing by) and stops first (the last running), and why one is left out (a fault, a heat trip, set by
  hand). It only acts when the number needed changes; it never swaps running ones to even them out. Side by side
  from 120 columns, else one above the other. BACK returns to the main page.

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

-- "1 and 2", "1, 2 and 3"
local function andList(list)
  if #list <= 1 then return table.concat(list) end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- tight: no scale under the marks and no blank rows (for 25 rows).
local function ladder(f, g, x, y, width, tight)
  local barW = math.max(20, math.min(40, width - 14))
  local bx = x + 6
  local function col(p) return bx + math.max(0, math.min(barW - 1, math.floor(p / 100 * barW))) end
  f:text(x, y, "fill", C.dim)
  f:bar(bx, y, barW, 1, g.fill or 0, C.good)
  f:text(bx + barW + 1, y, g.fill and ("%.1f%%"):format(g.fill * 100) or "?", C.text)
  for _, st in ipairs(g.steps) do f:text(col(st.onBelow), y + 1, "▲", st.active and C.text or C.dim) end
  f:text(x, y + 1, "marks", C.dim)
  if tight then
    y = y + 2
  else
    f:text(bx, y + 2, "0%", C.dim)
    f:text(col(50) - 1, y + 2, "50%", C.dim)
    f:text(bx + barW - 4, y + 2, "100%", C.dim)
    y = y + 4
  end
  f:text(x, y, "STEP", C.dim)
  f:text(x + 6, y, "ON BELOW", C.dim)
  f:text(x + 16, y, "OFF ABOVE", C.dim)
  f:text(x + 27, y, "RUNS", C.dim)
  f:text(x + 35, y, "NOW", C.dim)
  local cum, on, byMark = 0, {}, {}
  for k, st in ipairs(g.steps) do
    cum = cum + st.run
    y = y + 1
    local c = st.active and C.text or C.dim
    f:text(x, y, tostring(k), c)
    f:text(x + 6, y, ("%g%%"):format(st.onBelow), c)
    f:text(x + 16, y, ("%g%%"):format(st.offAbove), c)
    f:text(x + 27, y, tostring(cum) .. (k > 1 and (" (+%d)"):format(st.run) or ""), c)
    f:text(x + 35, y, st.active and "on" or "off", st.active and C.good or C.dim)
    if st.active then on[#on + 1] = tostring(k) end
    byMark[st.onBelow] = byMark[st.onBelow] or {}
    table.insert(byMark[st.onBelow], tostring(k))
  end

  y = y + (tight and 1 or 2)
  if g.fill and g.need then
    local steps = #on == 0 and "no step is on"
      or ((#on == 1 and "step " or "steps ") .. andList(on) .. (#on == 1 and " is on" or " are on"))
    local need = g.need == 1 and "so 1 is needed" or ("so %d are needed"):format(g.need)
    f:text(x, y, Gui.fit(("%.1f%% now: %s, %s"):format(g.fill * 100, steps, need), width), C.info)
  else
    f:text(x, y, Gui.fit(g.why or "can't read the LSC: holding", width), C.warn)
  end
  local marks = {}
  for mark, ks in pairs(byMark) do if #ks > 1 then marks[#marks + 1] = mark end end
  table.sort(marks, function(p, q) return p > q end)
  for _, mark in ipairs(marks) do
    y = y + 1
    local ks = byMark[mark]
    f:text(x, y, Gui.fit(("Steps %s %s start below %g%%, so together."):format(andList(ks),
      #ks == 2 and "both" or "all", mark), width), C.warn)
  end
  return y
end

-- A bar of `w` cells, `frac` of it in `color`, the rest dim; a little shorter than a row, so rows stay apart.
local function thinBar(f, x, y, w, frac, color)
  local n = math.floor(math.max(0, math.min(1, frac)) * w + 0.5)
  if n > 0 then f:text(x, y, string.rep("▇", n), color) end
  if n < w then f:text(x + n, y, string.rep("▇", w - n), C.line) end
end

local function order(f, g, x, y, width, last)
  local nameW = 8
  for _, s in ipairs(g.order) do nameW = math.max(nameW, Gui.len(s.name)) end
  nameW = math.min(nameW, 18)
  local barW = width >= 90 and 20 or 10
  local cols = { num = x, name = x + 3, now = x + 4 + nameW }
  cols.bar = cols.now + 15
  cols.note = cols.bar + barW + 8
  f:text(cols.num, y, "#", C.dim)
  f:text(cols.name, y, "SWITCH", C.dim)
  f:text(cols.now, y, "NOW", C.dim)
  f:text(cols.bar, y, "RUN TIME, 24 H", C.dim)
  if cols.note < x + width - 8 then f:text(cols.note, y, "NOTE", C.dim) end
  -- Who starts next (the first standing by) and stops first (the last running), among the members in the group.
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
    f:text(cols.name, row, Gui.fit(s.name, nameW), C.text)
    f:text(cols.now, row, Gui.fit(state, 14), colour)
    thinBar(f, cols.bar, row, barW, secs / 86400, s.on and C.good or C.dim)
    f:text(cols.bar + barW + 1, row, ago(secs), C.text)
    local note = out
    if not note and s == firstOff then note = g.rotate and "next to start: least run time" or "next to start" end
    if not note and s == lastOn then note = g.rotate and "first to stop: most run time" or "first to stop" end
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
  local why = "It only acts when the number needed changes; it doesn't swap running ones."
  if wide then
    f:text(2, 5, "LADDER", C.accent)
    f:text(10, 5, "how many run at each fill", C.dim)
    ladder(f, g, 2, 7, 57)
    local ox = 62
    f:text(ox, 5, "ORDER", C.accent)
    f:text(ox + 7, 5, Gui.fit("by run time over 24 h: the least starts first, the most stops first", f.w - ox - 7), C.dim)
    local y = order(f, g, ox, 7, f.w - ox, lastRow - 2)
    f:text(ox, y + 1, Gui.fit(why, f.w - ox), C.dim)
  else
    f:text(2, 5, "LADDER", C.accent)
    local y = ladder(f, g, 2, 6, f.w - 2, f.h < 30)
    f:text(2, y + 1, "ORDER", C.accent)
    f:text(9, y + 1, Gui.fit("by run time over 24 h", f.w - 10), C.dim)
    y = order(f, g, 2, y + 2, f.w - 2, lastRow - 1)
    f:text(2, y, Gui.fit(why, f.w - 2), C.dim)
  end
end

return group
