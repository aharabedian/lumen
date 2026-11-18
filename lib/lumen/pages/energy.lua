--[[ lumen.pages.energy: the last 24 hours' energy. A chart of what was made, stacked by group and source (and
  "other": what came in that no source accounts for), with the load as a line; a row each: EU, share, uptime,
  EU/t while running, starts, and at full; what came in and went out; and HEADROOM: everything at full against
  the average and peak load, as EU/t and as reactors. Wide: the legend and HEADROOM beside; narrow: below.
  BACK returns to the main page.

  energy.build(f, m, actions)   m.energy: lumen.energy.day's; actions.back()
  energy.COLORS                 the bands' colours, in order ("other" is dim)
]]

local Gui = require("lumen.gui")
local frame = require("lumen.frame")

local page = {}

local C = frame.C
local si, ago = frame.si, frame.ago

page.COLORS = { 0x4fd17a, 0x5eb4ff, 0xff9f43, 0xb48cff, 0x4fd1c5, 0xff7eb6, 0xe6d27a }

local function colorOf(b, k)
  if b.kind == "other" then return C.dim end
  return page.COLORS[(k - 1) % #page.COLORS + 1]
end

-- The average of a band's samples over [a, b] (sample indices), nil when none are kept there.
local function avg(samples, a, b)
  local sum, n = 0, 0
  for i = a, b do
    local v = samples[i]
    if v then sum, n = sum + v, n + 1 end
  end
  return n > 0 and sum / n or nil
end

local function niceMax(v)
  if v <= 0 then return 1 end
  local p = 10 ^ math.floor(math.log(v, 10))
  for _, k in ipairs({ 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10 }) do if v <= k * p then return k * p end end
  return 10 * p
end

local function chart(f, e, x, y, w, h)
  local n = e.last - e.first + 1
  local cols = {}
  local top = 0
  for c = 0, w - 1 do
    local a = e.first + math.floor(c * n / w)
    local b = math.max(a, e.first + math.floor((c + 1) * n / w) - 1)
    local col = { load = avg(e.load, a, b), bands = {} }
    local sum = 0
    for k, band in ipairs(e.bands) do
      local v = avg(band.samples, a, b) or 0
      sum = sum + v
      col.bands[k] = sum
    end
    col.sum = sum
    top = math.max(top, sum, col.load or 0)
    cols[c] = col
  end
  local max = niceMax(top * 1.05)
  for c = 0, w - 1 do
    local col = cols[c]
    local loadRow = col.load and math.min(h - 1, math.floor(col.load / max * h))
    for row = 0, h - 1 do
      local v = (row + 0.5) / h * max
      local bg = C.bg
      if v <= col.sum then
        local k = 1
        while col.bands[k] and col.bands[k] < v do k = k + 1 end
        bg = colorOf(e.bands[k], k)
      end
      if row == loadRow then f:text(x + c, y + h - 1 - row, "━", C.text, bg)       -- the load, over its band
      elseif bg ~= C.bg then f:text(x + c, y + h - 1 - row, " ", C.text, bg) end
    end
  end
  f:text(x + w + 1, y, si(max), C.dim)
  f:text(x + w + 1, y + h // 2, si(max / 2), C.dim)
  f:text(x + w + 1, y + h - 1, "0", C.dim)
  f:text(x, y + h, "-24h", C.dim)
  f:text(x + w // 2 - 2, y + h, "-12h", C.dim)
  f:text(x + w - 3, y + h, "now", C.dim)
end

local function pct(v) return v and ("%.0f%%"):format(v * 100) or "–" end

local function table_(f, e, x, y, w, last)
  local cols = { { "SOURCE", 20 }, { "EU, 24 H", 9 }, { "SHARE", 6 }, { "UPTIME", 7 }, { "AVG EU/t", 9 }, { "STARTS", 7 },
    { "FULL EU/t", 10 } }
  local cx = x
  for k, c in ipairs(cols) do
    if k == 1 then f:text(cx, y, c[1], C.dim) else f:text(cx, y, Gui.rfit(c[1], c[2]), C.dim) end
    cx = cx + c[2] + 1
  end
  local row = y + 1
  for k, b in ipairs(e.bands) do
    if row > last then break end
    if row == last and k < #e.bands then f:text(x, row, ("+%d more"):format(#e.bands - k + 1), C.dim); row = row + 1; break end
    local name = b.kind == "group" and ("%s (%d)"):format(b.name, b.members or #b.sources) or b.name
    if b.kind == "other" then name = "other (no source)" end
    local cells = { si(b.eu), pct(b.share), b.kind == "other" and "" or pct(b.on),
      b.avgOn and si(b.avgOn) or "", b.kind == "other" and "" or tostring(b.starts),
      b.full and (si(b.full)) or (b.kind == "other" and "" or "?") }
    f:text(x, row, "■", colorOf(b, k))
    f:text(x + 2, row, Gui.fit(name, 18), C.text)
    cx = x + cols[1][2] + 1
    for j, v in ipairs(cells) do
      f:text(cx, row, Gui.rfit(v, cols[j + 1][2]), j == 1 and C.text or C.dim)
      cx = cx + cols[j + 1][2] + 1
    end
    row = row + 1
  end
  if row <= last then
    local net = e.made - e.used
    f:text(x, row, Gui.fit(("came in %s · went out %s · LSC %s%s EU over the day (%d h of readings)"):format(si(e.made),
      si(e.used), net >= 0 and "+" or "", si(net), e.hours), w), C.dim)
    row = row + 1
  end
  return row
end

local function units(hr)
  return hr.unit and hr.unit.each > 0 and ("≈ %.1f %s reactors"):format(hr.spare / hr.unit.each, hr.unit.name) or ""
end

-- Narrow: three lines.
local function headroomShort(f, e, x, y, w)
  local hr = e.headroom
  f:text(x, y, "HEADROOM", C.accent)
  f:text(x, y + 1, Gui.fit(("at full %s · making %s · load now %s EU/t"):format(hr.full > 0 and si(hr.full) or "–",
    si(hr.making), hr.load and si(hr.load) or "–"), w), C.text)
  f:text(x, y + 2, Gui.fit(("load over 24 h: average %s, peak %s EU/t"):format(hr.avg and si(hr.avg) or "–",
    hr.peak and si(hr.peak) or "–"), w), C.text)
  if hr.spare then
    f:text(x, y + 3, Gui.fit(("spare at the peak %s EU/t  %s"):format(si(hr.spare), units(hr)), w), hr.spare >= 0 and C.good or C.bad)
  end
end

local function headroom(f, e, x, y, w, now)
  local hr = e.headroom
  f:text(x, y, "HEADROOM", C.accent)
  local function line(label, v, color)
    y = y + 1
    f:text(x, y, label, C.dim)
    f:text(x + 18, y, Gui.fit(v, w - 18), color or C.text)
  end
  line("at full", hr.full > 0 and (si(hr.full) .. " EU/t") or "– (nothing seen running yet)")
  if #hr.unknown > 0 then line("", ("+ %d never seen running"):format(#hr.unknown), C.dim) end
  line("making now", si(hr.making) .. " EU/t")
  line("load, now", hr.load and (si(hr.load) .. " EU/t") or "–")
  line("load, average", hr.avg and (si(hr.avg) .. " EU/t") or "–")
  line("load, peak", hr.peak and (si(hr.peak) .. " EU/t" .. (hr.peakAt and now and ("  " .. ago(now - hr.peakAt) .. " ago") or ""))
    or "–")
  if hr.spare then line("spare at the peak", si(hr.spare) .. " EU/t  " .. units(hr), hr.spare >= 0 and C.good or C.bad) end
  return y
end

function page.build(f, m, actions)
  local e = m.energy
  local bx = f:button(2, 3, "◀ BACK", actions.back)
  f:text(bx, 3, "ENERGY", C.accent)
  f:text(bx + 8, 3, Gui.fit("the last 24 hours: where the EU came from, and where it went", f.w - bx - 9), C.dim)
  local wide = f.w >= 120
  local legendW = wide and 34 or 0
  local chartW = f.w - 2 - legendW - 8
  -- The chart gets the rows the rest doesn't need: its axis, the table (a row per band, the totals), HEADROOM.
  local below = wide and (2 + math.max(#e.bands + 2, 8) + 2) or (2 + #e.bands + 2 + 1 + 4)
  local chartH = math.max(4, math.min(30, f.h - 1 - 4 - below))
  chart(f, e, 2, 5, chartW, chartH)
  if wide then
    local lx = f.w - legendW + 1
    f:text(lx, 5, "MADE, 24 H", C.dim)
    for k, b in ipairs(e.bands) do
      local y = 6 + k
      if y > 5 + chartH then break end
      f:text(lx, y, "■", colorOf(b, k))
      f:text(lx + 2, y, Gui.fit(b.kind == "other" and "other" or b.name, legendW - 10), C.text)
      f:text(f.w - 6, y, Gui.rfit(pct(b.share), 6), C.dim)
    end
    local ly = math.min(5 + chartH, 7 + #e.bands + 1)
    f:text(lx, ly, "━", C.text)
    f:text(lx + 2, ly, "load (out)", C.dim)
  end
  local ty = 5 + chartH + 2
  if wide then
    table_(f, e, 2, ty, 84, f.h - 2)
    f:text(2, f.h - 1, "AVG EU/t: while running (a group: each); FULL: the most seen running", C.dim)
    headroom(f, e, 92, ty, f.w - 92, m.time)
  else
    local y = table_(f, e, 2, ty, f.w - 2, f.h - 6)
    headroomShort(f, e, 2, y + 1, f.w - 2)
  end
end

return page
