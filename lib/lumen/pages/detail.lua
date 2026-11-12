--[[ lumen.pages.detail: one LSC (or the total) in full. Its fill history over 80 min, 8 h or 24 h (tap to
  choose), averages over 5 s, 5 min and 1 h, time to full or empty, loss, maintenance, wireless, capacitors,
  and the last 24 hours against the 24 before: EU in and out, the highest draw, the lowest fill, and how long
  each switch was on. BACK returns to the main page.

  detail.build(f, m, actions)
    m.detail = { reading, range = 1 | 2 | 3, ranges = { name... }, chart = { fill... }, day, before
                 (lumen.history h:day), time (the clock's now, for "3h ago") }
]]

local Gui = require("lumen.gui")
local power = require("lumen.power")
local frame = require("lumen.frame")
local mainPage = require("lumen.pages.main")

local detail = {}

local C = frame.C
local si, signed, ago = frame.si, frame.signed, frame.ago

local TIER = {}
for i, t in ipairs({ "ULV", "LV", "MV", "HV", "EV", "IV", "LuV", "ZPM", "UV", "UHV", "UEV", "UIV", "UMV", "UXV", "MAX" }) do
  TIER[t] = i
end

-- lumen.alerts.drain's "how", for people.
local DRAIN_TEXT = {
  standby = "standby: the switches are off until their mark",
  settling = "drain judged 10 min after switching on",
  ["keeping up"] = "generators keeping up",
}

local function cols(f, x, y, cells, widths, colors)
  local cx = x
  for i, s in ipairs(cells) do
    f:text(cx, y, i == 1 and Gui.fit(s, widths[i]) or Gui.rfit(s, widths[i]), colors and colors[i] or C.text)
    cx = cx + widths[i] + 1
  end
end

local function dayLine(d, time)
  if not d or d.hours == 0 then return "no readings yet" end
  local parts = { ("in %s EU"):format(si(d.inEu)), ("out %s EU"):format(si(d.outEu)),
    ("net %s EU"):format(signed(d.inEu - d.outEu)) }
  if d.peakOut then
    parts[#parts + 1] = ("peak draw %s EU/t (%s ago)"):format(si(d.peakOut), ago(time - (d.peakAt or time)))
  end
  if d.minFill then parts[#parts + 1] = ("lowest %.1f%%"):format(d.minFill * 100) end
  if d.hours < 24 then parts[#parts + 1] = ("(%d h of readings)"):format(d.hours) end
  return table.concat(parts, "   ")
end

function detail.build(f, m, actions)
  local d = m.detail
  local r = d.reading
  local width = f.w - 2
  local x, y = 2, 3
  f:button(x, y, "◀ BACK", actions.back)
  if not r then
    f:text(x, y + 2, "That LSC is gone.", C.dim)
    return
  end
  local pct = r.fill and ("%.1f%%"):format(r.fill * 100) or "–"
  local figures = ("%s / %s EU  %s"):format(si(r.stored), si(r.capacity), pct)
  f:text(x + 9, y, Gui.fit(r.name, math.max(1, width - 10 - Gui.len(figures))), C.accent)
  f:text(x + width - Gui.len(figures), y, figures, C.text)
  y = y + 1
  if not r.ok then
    f:text(x, y + 1, Gui.fit("can't be read: " .. tostring(r.err), width), C.bad)
    return
  end
  f:bar(x, y, width, 1, r.fill, C.good)
  y = y + 2

  -- What's below the chart: the table (4), facts (2), the days (3 + switches), alerts (2).
  local nSwitches = 0
  for _ in pairs(d.day and d.day.on or {}) do nSwitches = nSwitches + 1 end
  local below = 4 + 1 + 2 + 1 + 3 + nSwitches + 1 + 2
  local chartRows = math.max(2, f.h - 1 - y - 1 - below)

  local bx = x
  for k, name in ipairs(d.ranges) do bx = f:button(bx, y, name:upper(), function() actions.range(k) end, d.range == k) end
  f:text(bx + 1, y, "fill, newest on the right", C.dim)
  y = y + 1
  if #d.chart > 0 then f:chart(x, y, width, chartRows, d.chart)
  else f:text(x, y, "No history yet.", C.dim) end
  y = y + chartRows + 1

  local w = { 8, 12, 12, 12 }
  cols(f, x, y, { "EU/t", "5 s", "5 min", "1 h" }, w, { C.dim, C.dim, C.dim, C.dim })
  cols(f, x, y + 1, { "In", si(r.inEut), si(r.in5m), si(r.in1h) }, w)
  cols(f, x, y + 2, { "Out", si(r.outEut), si(r.out5m), si(r.out1h) }, w)
  local function netColor(v) return v and (v < 0 and C.bad or v > 0 and C.good) or C.dim end
  cols(f, x, y + 3, { "Net", signed(r.net), signed(r.net5m), signed(r.net1h) }, w,
    { C.text, netColor(r.net), netColor(r.net5m), netColor(r.net1h) })
  y = y + 5

  local eta, etaColor = mainPage.etaText(r)
  local facts = { eta }
  if DRAIN_TEXT[r.drainHow] then facts[#facts + 1] = DRAIN_TEXT[r.drainHow]
  elseif r.drainHow then facts[#facts + 1] = "drain alerts: " .. r.drainHow end
  if r.passiveLoss then facts[#facts + 1] = ("passive loss %s EU/t"):format(si(r.passiveLoss)) end
  facts[#facts + 1] = "maintenance " .. tostring(r.maintenance or "?")
  if r.wireless then
    local eu = (r.wirelessEu and r.wirelessEu > 0) and (" (" .. si(r.wirelessEu) .. " EU)") or ""
    facts[#facts + 1] = "wireless " .. r.wireless .. eu
  end
  f:text(x, y, Gui.fit(table.concat(facts, "   "), width), etaColor == C.warn and C.warn or C.text)
  if r.capacitors then
    local tiers = {}
    for tier, n in pairs(r.capacitors) do tiers[#tiers + 1] = { tier, n } end
    table.sort(tiers, function(a, b)
      local ra, rb = TIER[a[1]] or 99, TIER[b[1]] or 99
      if ra ~= rb then return ra < rb end
      return a[1] < b[1]
    end)
    local parts = {}
    for _, t in ipairs(tiers) do parts[#parts + 1] = t[1] .. " " .. tostring(t[2]) end
    f:text(x, y + 1, Gui.fit("capacitors: " .. table.concat(parts, " · "), width), C.dim)
  elseif r.count then
    f:text(x, y + 1, Gui.fit(("%d LSCs added up"):format(r.count), width), C.dim)
  end
  y = y + 3

  f:text(x, y, Gui.fit("LAST 24 H", 12), C.accent)
  f:text(x + 13, y, Gui.fit(dayLine(d.day, d.time), width - 13), C.text)
  f:text(x, y + 1, Gui.fit("24 H BEFORE", 12), C.dim)
  f:text(x + 13, y + 1, Gui.fit(dayLine(d.before, d.time), width - 13), C.dim)
  y = y + 2
  local names = {}
  for name in pairs(d.day and d.day.on or {}) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    f:text(x + 13, y, Gui.fit(("%s on for %s of the last 24 h (%s the day before)"):format(name,
      power.duration(d.day.on[name]) or "0s", power.duration((d.before.on or {})[name] or 0) or "0s"), width - 13), C.dim)
    y = y + 1
  end
  mainPage.alerts(f, m, x, f.h - 3, width, f.h - 1)
end

return detail
