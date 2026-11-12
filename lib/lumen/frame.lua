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

return frame
