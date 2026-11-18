--[[ lumen.pages.supplies: what generators burn and make, counted in the ME system (lumen.supplies). A row each:
  its stock, its change per hour over the last hour (and the day's), how long it lasts at that rate, its last 24
  hours as a line, its alert, and what it feeds. Narrow: no line, no feeds. BACK returns to the main page.

  supplies.build(f, m, actions)   m.supplies: lumen.supplies readings with rate, rate24 (per hour), lasts
                                  (seconds), chart (lumen.history h:supplyChart); m.time; actions.back()
]]

local Gui = require("lumen.gui")
local frame = require("lumen.frame")
local supplies = require("lumen.supplies")
local history = require("lumen.history")

local page = {}

local C = frame.C
local si = frame.si
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

local function signedRate(v)
  if not v then return "–" end
  if math.abs(v) < 0.05 then return "0" end
  return (v > 0 and "+" or "") .. si(v)
end

-- The last 24 hours of a supply's stock as w eighth-blocks, from its lowest to its highest that day (so a slow
-- trend shows); a flat one is half high.
local function spark(chart, time, w)
  local step = history.RANGES[3].step
  local last = math.floor(time / step)
  local first = last - math.floor(86400 / step) + 1
  local byI, top, low = {}, -math.huge, math.huge
  for _, p in ipairs(chart or {}) do
    if p.i >= first then byI[p.i] = p.v; top, low = math.max(top, p.v), math.min(low, p.v) end
  end
  local out = {}
  for c = 1, w do
    local a = first + math.floor((c - 1) * (last - first + 1) / w)
    local b = math.max(a, first + math.floor(c * (last - first + 1) / w) - 1)
    local sum, n = 0, 0
    for i = a, b do if byI[i] then sum, n = sum + byI[i], n + 1 end end
    local k = 0
    if n > 0 then k = top > low and math.floor(1 + (sum / n - low) / (top - low) * 7 + 0.5) or 4 end
    out[c] = k == 0 and " " or SPARK[math.min(8, k)]
  end
  return table.concat(out)
end

local function alertText(c)
  local parts = {}
  if c.below then parts[#parts + 1] = "under " .. si(c.below) end
  if c.above then parts[#parts + 1] = "over " .. si(c.above) end
  if c.hours then parts[#parts + 1] = ("< %g h left"):format(c.hours) end
  return #parts > 0 and table.concat(parts, ", ") or "–"
end

function page.build(f, m, actions)
  local bx = f:button(2, 3, "◀ BACK", actions.back)
  f:text(bx, 3, "SUPPLIES", C.accent)
  f:text(bx + 10, 3, Gui.fit("counted in the ME system every 30 s; per hour over the last hour", f.w - bx - 11), C.dim)
  local wide = f.w >= 120
  local cols = { { "SUPPLY", 22, "l" }, { "STOCK", 11, "r" }, { "PER HOUR", 10, "r" }, { "DAY'S", 9, "r" }, { "LASTS", 12, "l" } }
  if wide then
    cols[#cols + 1] = { "LAST 24 H", 32, "l" }
    cols[#cols + 1] = { "ALERT", 22, "l" }
    cols[#cols + 1] = { "FEEDS", 20, "l" }
  else
    cols[#cols + 1] = { "ALERT", 13, "l" }
  end
  local x = 2
  for _, c in ipairs(cols) do
    f:text(x, 5, c[3] == "r" and Gui.rfit(c[1], c[2]) or c[1], C.dim)
    c.x = x
    x = x + c[2] + 1
  end
  local list = m.supplies or {}
  if #list == 0 then
    f:text(2, 7, Gui.fit("None yet: add them in lumen-setup (SUPPLIES), with an adapter on an ME interface.", f.w - 2), C.dim)
    return
  end
  for k, r in ipairs(list) do
    local y = 6 + k
    if y > f.h - 2 then break end
    local level, text = supplies.status(r)
    local color = level == "bad" and C.bad or level == "warn" and C.warn or C.good
    local unit = supplies.unit(r.kind)
    local cells = {
      Gui.fit(r.name, cols[1][2] - 2),
      r.ok and (si(r.amount) .. unit) or "?",
      signedRate(r.rate),
      signedRate(r.rate24),
      text,
    }
    f:text(cols[1].x, y, "●", color)
    f:text(cols[1].x + 2, y, cells[1], C.text)
    f:text(cols[2].x, y, Gui.rfit(cells[2], cols[2][2]), C.text)
    f:text(cols[3].x, y, Gui.rfit(cells[3], cols[3][2]), C.dim)
    f:text(cols[4].x, y, Gui.rfit(cells[4], cols[4][2]), C.dim)
    f:text(cols[5].x, y, Gui.fit(cells[5], cols[5][2]), level and color or C.text)
    if wide then
      f:text(cols[6].x, y, spark(r.chart, m.time or 0, cols[6][2]), C.info)
      f:text(cols[7].x, y, Gui.fit(alertText(r.cfg or {}), cols[7][2]), C.dim)
      f:text(cols[8].x, y, Gui.fit(r.cfg and r.cfg.feeds or "", cols[8][2]), C.dim)
    else
      f:text(cols[6].x, y, Gui.fit(alertText(r.cfg or {}), cols[6][2]), C.dim)
    end
  end
end

return page
