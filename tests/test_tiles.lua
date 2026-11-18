-- test_tiles.lua: lumen's screen with a reactor fleet. Twelve IC2 reactors, each on its own Redstone I/O block,
-- in one group with heat trips, a breeder that's always on, and an LFTR no switch runs: tiles (a switch and its
-- reactor as one tile, the heat bar against its trip, RESET on a tripped or latched tile), the group's section,
-- line and page (ladder and order), "Not in a group" after it (the breeder with ON / OFF only), TILES / ROWS kept
-- across a restart, and how it fits a 160 x 50 screen, a 7 x 3 wall and a tier 2 screen.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local Gen = require("gen")
local check = H.check
local C = require("lumen.frame").C

local CAP = 2e11
local lsc = LSC.new{ stored = 0.72 * CAP, capacity = CAP, inSec = 0, outSec = 300000, in1h = 300000, out1h = 300000 }
local rs, reactors = {}, {}
M.components = { ["d2440f27-52c9"] = lsc.entry }
local lines = {}
for k = 1, 12 do
  rs[k] = Gen.redstone()
  reactors[k] = Gen.reactor{ heat = 5000 + k * 100, maxHeat = 10000, output = 44000, produces = false }
  M.components[("c%03d0000-0000"):format(k)] = rs[k].entry
  M.components[("e%03d0000-0000"):format(k)] = reactors[k].entry
  lines[#lines + 1] = ('    { name = "MOX %d", redstone = "c%03d", side = "top", group = "Nuclear", source = "Reactor %d", heatTrip = 90,'
    .. ' fault = { redstone = "c%03d", side = "south", latch = true } },'):format(k, k, k, k)
end
local breeder = Gen.reactor{ heat = 4000, maxHeat = 10000, output = 1320, produces = false }
rs[13] = Gen.redstone()
M.components["c0130000-0000"] = rs[13].entry
M.components["e0130000-0000"] = breeder.entry
lines[#lines + 1] = '    { name = "Breeder", redstone = "c013", side = "top", always = true, source = "Breeder", heatTrip = 75 },'
local lftr = Gen.gt("gtpp.multimachine.lftr", { active = true, lines = { "Current Output: 32,768 EU/t" } })
M.components["a1b20000-0000"] = lftr.entry
local srcLines = {}
for k = 1, 12 do srcLines[#srcLines + 1] = ('    { address = "e%03d", name = "Reactor %d" },'):format(k, k) end

local cfgPath = H.TMP .. "/lumen.cfg"
local fh = assert(io.open(cfgPath, "w"))
fh:write("return {\n  heatWarn = 95, heatBad = 98,\n  names = { d2440f27 = \"Main\" },\n  sources = {\n" .. table.concat(srcLines, "\n")
  .. '\n    { address = "e013", name = "Breeder" },\n    { address = "a1b2", name = "LFTR" },\n  },\n'
  .. '  groups = { { name = "Nuclear", steps = { { onBelow = 90, offAbove = 95, run = 4 }, { onBelow = 75, offAbove = 85, run = 6 },'
  .. ' { onBelow = 50, offAbove = 65, run = 2 } } } },\n  control = {\n' .. table.concat(lines, "\n") .. "\n  },\n}\n")
fh:close()

-- The world: a reactor runs while its block's top output (side 1) is on.
local function step()
  local n = 0
  for k = 1, 12 do
    local on = (rs[k].out[1] or 0) > 0
    reactors[k].state.produces = on
    if on then n = n + 1 end
  end
  breeder.state.produces = (rs[13].out[1] or 0) > 0
  lsc.state.inSec = n * 44000 + 32768 + (breeder.state.produces and 1320 or 0)
end

local function run(untilTime, onPull)
  M.pulls = 0
  local quitAt
  M.onPull = function(n)
    step()
    local ev = onPull and onPull(n, M.time)
    if ev then return ev end
    if M.time >= untilTime then
      if not quitAt then quitAt = n; return { "touch", "scr", M.W - 3, 1, 0, "p" } end
      return { "interrupted" }
    end
  end
  local errs = {}
  local realStderr = io.stderr
  io.stderr = { write = function(_, s) errs[#errs + 1] = s end } -- luacheck: ignore 122
  local ok, err = pcall(H.run, "lumen.lua", cfgPath)
  io.stderr = realStderr -- luacheck: ignore 122
  M.onPull = nil
  check(ok and #errs == 0, "runs without errors" .. ((ok and #errs == 0) and "" or (": " .. tostring(err or errs[1]))))
end
local function tapAt(text, minY, minX)
  local x, y = M.find(text, minY, minX)
  assert(x, "nothing to tap: " .. text)
  return { "touch", "scr", x + 1, y, 0, "p" }
end
local function running()
  local n = 0
  for k = 1, 12 do if (rs[k].out[1] or 0) > 0 then n = n + 1 end end
  return n
end

---------------------------------------------------------------- tiles on a tier 3 screen
M.resize(160, 50)
M.aspect = nil
M.setTime(0)
local seen = {}
run(40, function(_, t)
  if t > 30 and not seen.tiles then
    local mx, my = M.find("MOX 12 ", 3)
    local _, gy = M.find("▸ Nuclear", 3)
    local _, oy = M.find("Not in a group", 3)
    local bx, by = M.find("Breeder ", 3)
    local ax = by and M.find(" AUTO ", by + 4, bx - 3)
    seen.sections = gy and oy and my and by and gy < my and my < oy and oy < by and M.find("1 always on · 1 with no switch", oy)
    seen.breeder = by and M.find("ON · always", by) and M.find("always on: ON / OFF on the screen", by)
      and M.find(" OFF ", by + 4, bx) and (not ax or ax > bx + 36) and (rs[13].out[1] or 0) > 0
    seen.badge = M.find("STANDBY", 3) and M.find("standing by: 10 of 12 needed", 3)
    seen.tiles = {
      all = mx and M.find("MOX 1 ", 3) and not M.find("more tiles", 3),
      group = M.find("Nuclear", 3) and M.find("10 needed", 3),
      trip = M.find("trip 90%", 3),
      lftr = M.find("LFTR", 3) and M.find("32.77k EU/t", 3),
      title = mx and M.bgAt(mx, my) == C.line,
      buttons = M.find(" AUTO ", 3) and M.find(" TILES ", 3),
    }
    H.screen("lumen-tiles")
  end
end)
check(running() == 10, ("72%% full: the ladder runs 10 of 12 (%d)"):format(running()))
check(seen.tiles.all and seen.tiles.buttons, "a tile for each of the 12, with AUTO / ON / OFF; TILES chosen by itself")
check(seen.tiles.title, "a tile's title on its own colour")
check(seen.tiles.group, "the group's line: how many it needs")
check(seen.tiles.trip, "the heat bar says where it trips")
check(seen.tiles.lftr, "the LFTR (no switch) gets a tile too")
check(seen.sections, "the group's line with its members under it, then \"Not in a group\" and what's in it")
check(seen.breeder, "the breeder, always on: running, ON / OFF only (no AUTO), and says so")
check(seen.badge, "a member standing by says STANDBY, and how many of the group are needed")

---------------------------------------------------------------- a heat trip and a latched fault
local tripped
for k = 1, 12 do if (rs[k].out[1] or 0) > 0 and not tripped then tripped = k end end
reactors[tripped].state.heat = 9300
rs[1].inp[3] = 15
seen = {}
run(M.time + 20, function(n)
  if n == 3 then rs[1].inp[3] = 0 end
  if not seen.trip and (rs[tripped].out[1] or 0) == 0 then
    local x, y = M.find(("MOX %d "):format(tripped), 3)
    seen.trip = { red = x and M.bgAt(x, y) == C.bad, text = M.find("TRIP", 3) and M.find("heat 93%, trips at 90%", 3),
      reset = M.find(" RESET ", 3) }
  end
end)
check(seen.trip and seen.trip.red and seen.trip.text, "MOX " .. tripped .. " over 90%: off, its tile red, TRIP and why")
check(seen.trip.reset, "RESET on the tile")
local fx, fy = M.find("MOX 1 ", 3)
check(M.bgAt(fx, fy) == C.bad and M.find("fault", fy), "MOX 1's latched fault: red too")
reactors[tripped].state.heat = 9200
run(M.time + 20, function(n)
  if n == 2 then
    local _, y = M.find(("MOX %d "):format(tripped), 3)
    return tapAt(" RESET ", y)
  end
end)
check(not M.find("TRIP", 3) and M.find("trip 97%", 3) and running() == 10,
  "RESET at 92%: back in the group, 10 running; it trips at 97% until it cools")

---------------------------------------------------------------- the group's page
seen = {}
run(M.time + 20, function(n)
  if n == 2 then return tapAt("Nuclear", 3) end
  if n == 4 then
    seen.page = M.find("◀ BACK", 3) and M.find("LADDER", 3) and M.find("ORDER", 3)
      and M.find("72.0% now: steps 1 and 2 are on, so 10 are needed", 3)
    seen.order = M.find("RUN TIME, 24 H", 3) and M.find("MOX 12", 3)
    H.screen("lumen-group")
  end
  if n == 5 then return tapAt("◀ BACK", 3) end
  if n == 7 then seen.back = M.find(" TILES ", 3) ~= nil end
end)
check(seen.page, "tap the group: its ladder, with the fill now")
check(seen.order, "and its order by run time")
check(seen.back, "BACK: the main page")

---------------------------------------------------------------- ROWS, kept across a restart
seen = {}
run(M.time + 10, function(n)
  if n == 2 then return tapAt(" ROWS ", 3) end
  if n == 4 then
    seen.rows = M.find("10 of 12 needed", 3) and not M.find("trip 90%", 3) and M.find("Not in a group", 3)
      and M.find("always on: ON / OFF on the screen", 3)
  end
end)
check(seen.rows, "ROWS: the same sections, each member saying what the group wants")
run(M.time + 10)
check(M.find(" ROWS ", 3) and not M.find("trip 90%", 3), "a restart keeps ROWS")
run(M.time + 10, function(n) if n == 2 then return tapAt(" TILES ", 3) end end)

---------------------------------------------------------------- a 7 x 3 wall, and tier 2
M.aspect = { 7, 3 }
M.oob = 0
run(M.time + 10)
H.screen("lumen-tiles-wall")
check(M.resolution[2] == 33 and M.oob == 0 and M.find("MOX 12 ", 3) and not M.find("more tiles", 3),
  "a 7 x 3 wall (160 x 33): all twelve tiles fit")
M.aspect = nil
M.resize(80, 25)
M.oob = 0
run(M.time + 10)
H.screen("lumen-tiles-tier2")
check(M.oob == 0 and M.find("POWER", 3) and M.find("more tiles", 3), "tier 2: as many tiles as fit, and how many more")
M.resize(160, 50)

---------------------------------------------------------------- the group page, from a model
-- Four reactors with long names; steps 1 and 2 share the 75% mark; the fill (71.8%) just under it.
local frame = require("lumen.frame")
local groupPage = require("lumen.pages.group")
local function text(f)
  local rows = {}
  for y = 1, f.h do
    local cells = {}
    for x = 1, f.w do cells[x] = " " end
    for _, seg in ipairs(f.rows[y].segs) do
      local i = 0
      for _, cp in utf8.codes(seg[2]) do
        if seg[1] + i <= f.w then cells[seg[1] + i] = utf8.char(cp) end
        i = i + 1
      end
    end
    rows[y] = table.concat(cells)
  end
  return table.concat(rows, "\n")
end
local function member(name, on, hours)
  return { name = name, on = on, mode = "auto", index = tonumber(name:sub(-1)), cfg = {}, hrs = hours * 3600 }
end
local ms = { member("Reactor N-1", true, 4 + 55 / 60), member("Reactor N-2", false, 7 + 49 / 60),
  member("Reactor N-3", false, 8 + 7 / 60), member("Reactor N-4", true, 8 + 44 / 60) }
local hours = {}
for _, s in ipairs(ms) do hours[s.name] = s.hrs end
local g = { name = "Quad Uranium", rotate = true, fill = 0.718, need = 2, running = 2, members = ms, order = ms, hours = hours,
  steps = { { onBelow = 75, offAbove = 90, run = 1, active = true }, { onBelow = 75, offAbove = 90, run = 1, active = true },
    { onBelow = 70, offAbove = 90, run = 2, active = false } } }
for _, size in ipairs({ { 160, 33 }, { 80, 25 } }) do
  local f = frame.new(size[1], size[2])
  groupPage.build(f, { group = g }, { back = function() end })
  local t = text(f)
  local tag = (" at %d x %d"):format(size[1], size[2])
  check(t:find("Reactor N-1", 1, true) and t:find("Reactor N-4", 1, true), "every member's whole name" .. tag)
  check(t:find("1     75%       90%        1", 1, true) and t:find("2     75%       90%        2", 1, true)
    and t:find("3     70%       90%        4", 1, true), "each step: its marks and how many run in all, none hidden" .. tag)
  check(t:find("71.8% now: steps 1 and 2 are on, so 2 are needed", 1, true), "the fill now and why that many" .. tag)
  check(t:find("Steps 1 and 2 both start below 75%", 1, true), "steps sharing a mark say so" .. tag)
  check(t:find("next to start", 1, true) and t:find("first to stop", 1, true) and t:find("doesn't swap", 1, true),
    "who starts next and stops first, and that running ones aren't swapped" .. tag)
end

H.done()
