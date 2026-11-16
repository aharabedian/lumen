--[[ lumen.frame: a screen being built, as rows of text segments and touch targets, and the widgets the pages
  draw with. Knows nothing about the game.

  frame.new(w, h) -> f
  f:text(x, y, s, fg?, bg?)          clipped to the screen
  f:rowBg(y, bg)
  f:hit(x1, y1, x2, y2, fn)          a touch target (later ones win)
  f:button(x, y, label, fn, on?) -> x after it    " LABEL ", highlighted when on
  f:bar(x, y, width, rows, fill, color)           a fill bar
  f:chart(x, y, width, rows, values)              values 0..1 as an eighth-block chart, newest on the right
  f.rows[y] = { bg, segs = { { x, text, fg, bg }... } }, f.hits
  frame.paint(ui, last, f)           send a lumen.gui ui only the rows that changed since the last paint;
                                     last: a table the caller keeps (empty at first, or to repaint everything)
  frame.tap(hits, x, y) -> bool      run the touch target under (x, y) (the last one drawn wins)
  frame.si, frame.signed(v), frame.ago(seconds)   "4.20k", "+4.20k", "3h05m"
  frame.C                                         the palette (lumen.gui)
]]

local Gui = require("lumen.gui")
local power = require("lumen.power")

local frame = {}

local C = Gui.C
frame.C = C
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

frame.si = power.si

function frame.signed(v)
  if v == nil then return "–" end
  if v > 0 then return "+" .. power.si(v) end
  return power.si(v)
end

function frame.ago(s)
  s = math.max(0, math.floor(s or 0))
  if s < 60 then return s .. "s" end
  if s < 3600 then return (s // 60) .. "m" end
  return ("%dh%02dm"):format(s // 3600, (s % 3600) // 60)
end

local F = {}
F.__index = F

function frame.new(w, h)
  local rows = {}
  for y = 1, h do rows[y] = { bg = C.bg, segs = {} } end
  return setmetatable({ w = w, h = h, rows = rows, hits = {} }, F)
end

function F:text(x, y, s, fg, bg)
  if y < 1 or y > self.h or x > self.w or x < 1 then return end
  local room = self.w - x + 1
  if Gui.len(s) > room then s = Gui.fit(s, room) end
  local segs = self.rows[y].segs
  segs[#segs + 1] = { x, s, fg or C.text, bg or self.rows[y].bg }
end

function F:rowBg(y, bg) if self.rows[y] then self.rows[y].bg = bg end end
function F:hit(x1, y1, x2, y2, fn) self.hits[#self.hits + 1] = { x1, y1, x2, y2, fn } end

function F:button(x, y, label, fn, on)
  local s = " " .. label .. " "
  self:text(x, y, s, C.text, on and C.btnOn or C.btn)
  local x2 = x + Gui.len(s) - 1
  if fn then self:hit(x, y, x2, y, fn) end
  return x2 + 2
end

function F:bar(x, y, width, rows, fill, color)
  local filled = math.floor(math.max(0, math.min(1, fill or 0)) * width + 0.5)
  for by = y, y + rows - 1 do
    if filled > 0 then self:text(x, by, string.rep(" ", filled), C.text, color) end
    if filled < width then self:text(x + filled, by, string.rep(" ", width - filled), C.text, C.line) end
  end
end

function F:chart(x, y, width, rows, values)
  local n = #values
  local first = math.max(1, n - width + 1)
  for k = rows - 1, 0, -1 do
    local out = {}
    for i = first, n do
      local level = math.max(0, math.min(1, values[i] or 0)) * rows * 8 - k * 8
      level = math.floor(math.max(0, math.min(8, level)) + 0.5)
      out[#out + 1] = level == 0 and " " or SPARK[level]
    end
    self:text(x, y + (rows - 1 - k), table.concat(out), C.info)
  end
end

local function rowKey(row)
  local parts = { row.bg }
  for _, s in ipairs(row.segs) do parts[#parts + 1] = s[1] .. "\1" .. s[2] .. "\1" .. s[3] .. "\1" .. s[4] end
  return table.concat(parts, "\2")
end

-- Whether any two segments of a row cover the same cell (a button drawn over text).
local function overlaps(segs)
  local spans = {}
  for _, sg in ipairs(segs) do spans[#spans + 1] = { sg[1], sg[1] + Gui.len(sg[2]) - 1 } end
  table.sort(spans, function(a, b) return a[1] < b[1] end)
  for i = 2, #spans do if spans[i][1] <= spans[i - 1][2] then return true end end
  return false
end

-- Same background and the same segments at the same places with the same widths, none over another: only
-- texts or colors changed, so those segments can be redrawn in place.
local function sameShape(a, b)
  if not a or a.bg ~= b.bg or #a.segs ~= #b.segs then return false end
  for i, sa in ipairs(a.segs) do
    local sb = b.segs[i]
    if sa[1] ~= sb[1] or Gui.len(sa[2]) ~= Gui.len(sb[2]) then return false end
  end
  return not overlaps(b.segs)
end

function frame.paint(ui, last, f)
  for y = 1, f.h do
    local row = f.rows[y]
    local key = rowKey(row)
    local was = last[y]
    if not was or was.key ~= key then
      if sameShape(was and was.row, row) then
        for i, sg in ipairs(row.segs) do
          local old = was.row.segs[i]
          if old[2] ~= sg[2] or old[3] ~= sg[3] or old[4] ~= sg[4] then ui.put(sg[1], y, sg[2], sg[3], sg[4]) end
        end
      else
        ui.fill(1, y, f.w, 1, row.bg)
        for _, sg in ipairs(row.segs) do ui.put(sg[1], y, sg[2], sg[3], sg[4]) end
      end
      last[y] = { key = key, row = row }
    end
  end
end

function frame.tap(hits, x, y)
  for i = #hits, 1, -1 do
    local h = hits[i]
    if x >= h[1] and x <= h[3] and y >= h[2] and y <= h[4] then
      if h[5] then h[5]() end
      return true
    end
  end
  return false
end

return frame
