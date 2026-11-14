--[[ lumen.gui: drawing primitives and colors for the LUMEN screen. The same as LENS's lens.gui and PRISM's
  prism.gui (same palette, so the three look like one family).

  Gui.new(gpu, w, h) -> ui     sets the resolution to w x h
  ui.W, ui.H, ui.C, ui.gpu     screen size, colors, the GPU
  ui.put(x, y, s, fg?, bg?)    text; colors are only sent to the GPU when they change
  ui.fill(x, y, w, h, bg, ch?)
  ui.fg(c), ui.bg(c)
  ui.restore()                 back to plain terminal colors
  Gui.C                        the color palette
  Gui.len(s), Gui.fit(s, n), Gui.rfit(s, n)   text helpers (also on ui)
]]

local unicode = require("unicode")

local Gui = {}

-- The SPECTRA logo's colors (ink, background, a project each) with neutral greys between.
Gui.C = {
  bg     = 0x0b0e11, panel = 0x1a2129, line  = 0x2c3640,
  text   = 0xe6eaee, dim   = 0x7d8a96, accent = 0x4fd17a,   -- accent: LUMEN's color in the SPECTRA logo
  good   = 0x4fd17a, bad   = 0xff5c5c, warn  = 0xffd24d, info = 0x5eb4ff,
  btn    = 0x2c3640, btnOn = 0x2f6fb5, sel   = 0x24384d, field = 0x07090c,
}

function Gui.len(s) return unicode.len(s) end

-- s cut (with …) or padded to exactly n columns.
function Gui.fit(s, n)
  s = tostring(s or "")
  if n <= 0 then return "" end
  local l = unicode.len(s)
  if l > n then return unicode.sub(s, 1, n - 1) .. "…" end
  return s .. string.rep(" ", n - l)
end

-- s right-aligned in n columns.
function Gui.rfit(s, n)
  s = tostring(s or "")
  local l = unicode.len(s)
  if l >= n then return unicode.sub(s, 1, n) end
  return string.rep(" ", n - l) .. s
end

function Gui.new(gpu, W, H)
  gpu.setResolution(W, H)
  local C = Gui.C
  local ui = { W = W, H = H, C = C, gpu = gpu, len = Gui.len, fit = Gui.fit, rfit = Gui.rfit }

  local curFg, curBg
  function ui.fg(c) if c ~= curFg then gpu.setForeground(c); curFg = c end end
  function ui.bg(c) if c ~= curBg then gpu.setBackground(c); curBg = c end end
  function ui.put(x, y, s, f, b)
    if b then ui.bg(b) end
    ui.fg(f or C.text)
    gpu.set(x, y, s)
  end
  function ui.fill(x, y, w, h, b, ch)
    if w > 0 and h > 0 then ui.bg(b); gpu.fill(x, y, w, h, ch or " ") end
  end

  function ui.restore()
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
  end

  return ui
end

return Gui
