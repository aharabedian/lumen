--[[ lumen.pages.timeline: what happened. 8 H, 24 H or 7 D: the fill and how many switches ran, then a bar per
  switch coloured by its state (on, on by hand, off, off by hand, fault, trip, error; blank while LUMEN wasn't
  running) with its time on; then the events, newest first, filtered (ALL, SWITCHES, FAULTS, BY HAND, ALERTS),
  with who tapped. ▲ ▼ page through older events. BACK returns to the main page.

  timeline.build(f, m, actions)   m.timeline: lumen.timeline.build's, with offset (events skipped, for paging);
                                  actions = { back(), range(k), filter(id), older(), newer() }
  timeline.cols(w) -> columns the bars get on a screen w wide (for lumen.timeline.build)
  timeline.COLORS                 { [state] = colour }
]]

local Gui = require("lumen.gui")
local frame = require("lumen.frame")
local model = require("lumen.timeline")

local page = {}

local C = frame.C
local ago = frame.ago
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local NAME_W = 14

page.COLORS = { on = C.good, hand = C.info, off = C.panel, handoff = C.line, fault = C.bad, trip = 0xff9f43, err = C.warn }
local KIND = { ON = C.good, OFF = C.line, FAULT = C.bad, TRIP = 0xff9f43, CLEAR = C.line, RESET = C.info, HAND = C.info,
  BAD = C.bad, WARN = C.warn, GONE = C.line, START = C.line, STOP = C.line }

function page.cols(w) return math.max(10, w - 2 - NAME_W - 1 - 9) end

local function spark(f, x, y, values, n, color)
  local out = {}
  for c = 1, n do
    local v = values[c]
    local k = v and math.floor(math.max(0, math.min(1, v)) * 8 + 0.5) or 0
    out[c] = k == 0 and " " or SPARK[k]
  end
  f:text(x, y, table.concat(out), color)
end

function page.build(f, m, actions)
  local t = m.timeline
  local bx = f:button(2, 3, "◀ BACK", actions.back)
  f:text(bx, 3, "TIMELINE", C.accent)
  bx = bx + 10
  for k, rg in ipairs(model.RANGES) do bx = f:button(bx, 3, rg.name, function() actions.range(k) end, t.range == k) end
  -- The filters at the right of the same row, or on the next when they don't fit.
  local need = 0
  for _, fl in ipairs(model.FILTERS) do need = need + Gui.len(fl.name) + 3 end
  local fx, fy = f.w + 1, 3
  if f.w - need <= bx + 1 then fx, fy = 2 + need, 4 end
  for k = #model.FILTERS, 1, -1 do
    local fl = model.FILTERS[k]
    fx = fx - Gui.len(fl.name) - 3
    f:button(fx, fy, fl.name, function() actions.filter(fl.id) end, t.filter == fl.id)
  end

  local x0 = 2 + NAME_W + 1
  local cols = page.cols(f.w)
  local span = model.RANGES[t.range].span
  local marks = span >= 7 * 86400 and { "-7d", "-5d", "-3d", "-1d" } or (span >= 86400 and { "-24h", "-18h", "-12h", "-6h" })
    or { "-8h", "-6h", "-4h", "-2h" }
  for k, l in ipairs(marks) do f:text(x0 + math.floor((k - 1) * cols / 4), 5, l, C.dim) end
  f:text(x0 + cols - 3, 5, "now", C.dim)
  f:text(2, 6, "fill", C.dim)
  if t.fill then spark(f, x0, 6, t.fill, cols, C.info) else f:text(x0, 6, "the fill's kept for 24 hours", C.dim) end
  f:text(2, 7, "running", C.dim)
  spark(f, x0, 7, t.running, cols, C.good)

  -- The bars: as many as fit above at least four events.
  local evRows = math.max(4, math.floor((f.h - 9) / 3))
  local lastBar = f.h - 2 - evRows - 3
  local y = 9
  for k, row in ipairs(t.rows) do
    if y > lastBar then
      f:text(2, y - 1, ("+%d more switches"):format(#t.rows - k + 1), C.dim)
      break
    end
    f:text(2, y, Gui.fit(row.name, NAME_W), C.text)
    for c = 1, cols do
      local st = row.cells[c]
      if st and st ~= "gone" then f:text(x0 + c - 1, y, " ", C.text, page.COLORS[st] or C.panel) end
    end
    f:text(x0 + cols + 1, y, Gui.rfit(ago(row.on), 8), C.dim)
    y = y + 1
  end
  local lx = 2
  for _, l in ipairs({ { "on", "on" }, { "hand", "on by hand" }, { "off", "off" }, { "handoff", "off by hand" },
    { "fault", "fault" }, { "trip", "trip" }, { "err", "error" } }) do
    if lx + Gui.len(l[2]) + 4 > f.w then break end
    f:text(lx, y, "  ", C.text, page.COLORS[l[1]])
    lx = lx + 3
    f:text(lx, y, l[2], C.dim)
    lx = lx + Gui.len(l[2]) + 2
  end
  if lx + 18 < f.w then f:text(f.w - 17, y, Gui.rfit("time on", 8), C.dim) end

  -- Events.
  y = y + 2
  local list, offset = t.events, m.timeline.offset or 0
  f:text(2, y, "EVENTS", C.accent)
  local room = f.h - 2 - y
  local shown = math.max(0, math.min(room, #list - offset))
  f:text(10, y, #list == 0 and "none kept yet" or ("%d-%d of %d, newest first · kept 7 days"):format(offset + 1, offset + shown,
    #list), C.dim)
  if #list > room then
    local px = f:button(f.w - 17, y, "▲ NEWER", actions.newer, false)
    f:button(px - 1, y, "▼ OLDER", actions.older, false)
  end
  for k = 1, shown do
    local e = list[offset + k]
    local ry = y + k
    f:text(2, ry, Gui.rfit(ago((m.time or e.time) - e.time), 7), C.dim)
    f:text(10, ry, Gui.fit(e.who, NAME_W), C.text)
    local kc = KIND[e.kind] or C.line
    f:text(10 + NAME_W + 1, ry, Gui.fit(" " .. e.kind, 7), kc == C.line and C.text or C.bg, kc)
    local text = e.player and (e.player .. ": " .. e.text) or e.text
    f:text(10 + NAME_W + 9, ry, Gui.fit(text, math.max(0, f.w - (10 + NAME_W + 9))), C.text)
  end
end

return page
