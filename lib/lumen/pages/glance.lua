--[[ lumen.pages.glance: big mode, for across the room. How full (in big digits), time to full or empty, the net,
  how many sources run, each group, switches in trouble, a fill bar, and the worst alert. Tap anywhere to wake.
  Beside the digits when there's room, else under them.

  glance.build(f, m, actions)   f: a frame at big mode's resolution (40 x 10 or more); m: lumen.screen's model;
                                actions.wake()
]]

local Gui = require("lumen.gui")
local frame = require("lumen.frame")
local mainPage = require("lumen.pages.main")
local supplies = require("lumen.supplies")

local glance = {}

local C = frame.C
local signed = frame.signed

-- 3 x 5 digits; each dot is two characters wide, so they come out about square.
local DIG = {
  ["0"] = { "111", "101", "101", "101", "111" }, ["1"] = { "010", "110", "010", "010", "111" },
  ["2"] = { "111", "001", "111", "100", "111" }, ["3"] = { "111", "001", "111", "001", "111" },
  ["4"] = { "101", "101", "111", "001", "001" }, ["5"] = { "111", "100", "111", "001", "111" },
  ["6"] = { "111", "100", "111", "101", "111" }, ["7"] = { "111", "001", "010", "010", "010" },
  ["8"] = { "111", "101", "111", "101", "111" }, ["9"] = { "111", "101", "111", "001", "111" },
  ["%"] = { "101", "001", "010", "100", "101" }, ["-"] = { "000", "000", "111", "000", "000" },
}
glance.DIGIT_W = 8   -- columns per digit, with the gap

local function big(f, x, y, text, color)
  for i = 1, #text do
    local g = DIG[text:sub(i, i)]
    if g then
      for row = 1, 5 do
        for col = 1, 3 do
          if g[row]:sub(col, col) == "1" then
            f:text(x + (i - 1) * glance.DIGIT_W + (col - 1) * 2, y + row - 1, "  ", C.text, color)
          end
        end
      end
    end
  end
end

local HEALTH_COLOR = { ok = C.good, warn = C.warn, bad = C.bad }
local HEALTH_TEXT = { ok = "OK", warn = "WARN", bad = "BAD" }

-- The lines beside (or under) the digits: { text, colour }...
local function lines(m, r)
  local out = {}
  if r and r.ok then
    local eta, etaColor = mainPage.etaText(r)
    out[#out + 1] = { eta, etaColor }
    out[#out + 1] = { ("net %s EU/t"):format(signed(r.net)), C.text }
  elseif r then
    out[#out + 1] = { "can't be read", C.bad }
  else
    out[#out + 1] = { "no LSC found", C.dim }
  end
  local n, on = 0, 0
  for _, src in ipairs(m.sources or {}) do
    n = n + 1
    if src.ok and src.active then on = on + 1 end
  end
  if n > 0 then out[#out + 1] = { ("%d of %d running"):format(on, n), on > 0 and C.good or C.dim } end
  for _, g in ipairs(m.groups or {}) do
    local t = g.need and ("%s %d of %d on"):format(g.name, g.running or 0, #g.members) or (g.name .. ": " .. (g.why or "?"))
    out[#out + 1] = { t, C.text }
  end
  local faults, trips, errs = 0, 0, 0
  for _, s in ipairs(m.switches or {}) do
    if s.trip and s.trip.on then trips = trips + 1
    elseif s.fault and s.fault.on then faults = faults + 1
    elseif s.err then errs = errs + 1 end
  end
  local parts = {}
  if faults > 0 then parts[#parts + 1] = faults .. " FAULT" end
  if trips > 0 then parts[#parts + 1] = trips .. " TRIP" end
  if errs > 0 then parts[#parts + 1] = errs .. " ERROR" end
  if #parts > 0 then out[#out + 1] = { table.concat(parts, " · "), C.bad } end
  for _, s in ipairs(m.supplies or {}) do
    local level, text = supplies.status(s)
    if level then out[#out + 1] = { s.name .. ": " .. text, level == "bad" and C.bad or C.warn } end
  end
  return out
end

function glance.build(f, m, actions)
  f:hit(1, 1, f.w, f.h, actions.wake)
  f:rowBg(1, C.panel)
  f:text(2, 1, "LUMEN", C.accent, C.panel)
  f:text(9, 1, " " .. (HEALTH_TEXT[m.health] or "?") .. " ", C.bg, HEALTH_COLOR[m.health] or C.dim)
  f:text(f.w - 11, 1, "tap to wake", C.dim, C.panel)

  local r = m.total or m.lscs[1]
  local pct = r and r.ok and r.fill and math.floor(r.fill * 100) or nil
  local digits = pct and (pct .. "%") or "--"
  local level = r and mainPage.levelOf(r, m.alerts)
  local color = level == "bad" and C.bad or level == "warn" and C.warn or C.good
  big(f, 3, 3, digits, pct and color or C.dim)

  local list = lines(m, r)
  local dw = #digits * glance.DIGIT_W - 2
  local barY = f.h - 2
  local x, y, last = 3 + dw + 4, 3, barY - 1
  if f.w - x + 1 < 18 then x, y = 3, 9 end                -- no room beside the digits: under them
  for _, l in ipairs(list) do
    if y > last then break end
    f:text(x, y, Gui.fit(l[1], f.w - x), l[2])
    y = y + 1
  end

  if r and r.ok then f:bar(2, barY, f.w - 2, 1, r.fill, color) end
  local a = (m.alerts or {})[1]
  if a then
    f:text(2, f.h, a.level == "bad" and " BAD  " or " WARN ", C.bg, a.level == "bad" and C.bad or C.warn)
    f:text(9, f.h, Gui.fit(a.text, f.w - 9), C.text)
  else
    f:text(2, f.h, "All good.", C.good)
  end
end

return glance
