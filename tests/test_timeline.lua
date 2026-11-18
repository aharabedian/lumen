-- test_timeline.lua: what happened. lumen.log (events kept 7 days in a file, added to as they happen, filtered),
-- lumen.history's switch states (changes kept 7 days, as segments), lumen.timeline's model (a cell per column, the
-- worst state in it winning, so a short fault shows on 7 D), lumen.control's events (on and off and why, faults,
-- trips, resets, modes set by hand), then the TIMELINE page in lumen: bars, events with who tapped, filters, and
-- the log across a restart; at 160 x 33 and 80 x 25.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local Gen = require("gen")
local check = H.check
local component = require("component")
local log = require("lumen.log")
local history = require("lumen.history")
local timeline = require("lumen.timeline")
local config = require("lumen.config")
local control = require("lumen.control")

---------------------------------------------------------------- lumen.log
local path = H.TMP .. "/lumen-log.cfg"
local T = 1.8e9
local L = log.new(path, T)
L:add(T - 8 * 86400, "ON", "Old", "too old to keep")
L:add(T, "ON", "MOX 1", "starting: 2 of 4\tneeded\n")
L:add(T + 10, "HAND", "MOX 2", "set OFF (was AUTO)", "Steve")
L:add(T + 20, "BAD", "alert", "Main nearly empty: 9.0%")
L:add(T + 30, "FAULT", "MOX 3", "fault signal")
check(#L.list == 4 and L.list[1].who == "MOX 1", "events kept in order; one older than 7 days dropped")
local L2 = log.new(path, T + 40)
check(#L2.list == 4 and L2.list[1].text == "starting: 2 of 4 needed " and L2.list[2].player == "Steve",
  "read back from the file, tabs and line breaks made spaces, who tapped kept")
local function kinds(list) local o = {} for _, e in ipairs(list) do o[#o + 1] = e.kind end return table.concat(o, " ") end
check(kinds(L2:recent("all")) == "FAULT BAD HAND ON", "newest first")
check(kinds(L2:recent("switches")) == "ON" and kinds(L2:recent("faults")) == "FAULT" and kinds(L2:recent("hand")) == "HAND"
  and kinds(L2:recent("alerts")) == "BAD", "filters: switches, faults, by hand, alerts")
for k = 1, 120 do L2:add(T + 40 + k, "OFF", "MOX 1", "above 90%") end
local L3 = log.new(path, T + 8 * 86400)
check(#L3.list == 0, "a week later, nothing kept")
local f = io.open(path)
local lines = 0
for _ in f:lines() do lines = lines + 1 end
f:close()
check(lines == 0, "and once it holds well over what's kept, the file is rewritten without them")

---------------------------------------------------------------- switch states
local h = history.new()
h:state("MOX 1", "off", T)
h:state("MOX 1", "on", T + 100)
h:state("MOX 1", "on", T + 200)
h:state("MOX 1", "fault", T + 300)
h:state("MOX 1", "off", T + 360)
local segs = h:segments("MOX 1", T, T + 1000)
check(#segs == 4 and segs[2].state == "on" and segs[2].from == T + 100 and segs[2].to == T + 300 and segs[4].to == T + 1000,
  "states kept as changes; segments over a span")
h:state("MOX 1", "on", T + 8 * 86400)
check(#h.states["MOX 1"] <= 2, "changes older than 7 days dropped")

local h2 = history.new()
local W = 7 * 86400
h2:state("MOX 1", "on", T - W + 1)
h2:state("MOX 1", "fault", T - 3 * 86400)
h2:state("MOX 1", "on", T - 3 * 86400 + 60)                -- a one-minute fault
h2:state("MOX 2", "off", T - W + 1)
h2:state("MOX 2", "hand", T - 3600)
local tm = timeline.build(h2, L2, { switches = { { name = "MOX 1" }, { name = "MOX 2" } } }, T, 3, "all", 140)
local faults = 0
for _, st in pairs(tm.rows[1].cells) do if st == "fault" then faults = faults + 1 end end
check(faults == 1 and tm.rows[1].on > W - 120, "7 D: a one-minute fault still shows; time on adds up")
check(tm.rows[2].cells[140] == "hand" and tm.rows[2].cells[1] == "off", "on by hand at the end, off before")
check(tm.running[140] == 1 and tm.running[1] == 0.5 and not tm.fill, "how many ran per column; no fill kept for 7 days")

---------------------------------------------------------------- control's events
local rs, flt = Gen.redstone(), Gen.redstone()
M.components = { ["5e1f0000-0000"] = rs.entry, ["9c1e0000-0000"] = flt.entry }
local cfg = config.check({ control = { { name = "Vac", redstone = "5e1f", side = "north", onBelow = 30, offAbove = 90,
  source = "Vac reactor", heatTrip = 90, fault = { redstone = "9c1e", side = "top" } } } })
local function at(fill) return { name = "All LSCs", address = "", ok = true, fill = fill } end
local main = { name = "Main", address = "d244", ok = true }
local c = control.new(component, cfg)
local function src(p) return { sources = { { name = "Vac reactor", ok = true, heat = p / 100, active = true } } } end
c:update({ main }, at(0.5), 0, src(10))
check(#c:drain() == 0, "the first look: nothing to say")
c:update({ main }, at(0.2), 100, src(10))
local ev = c:drain()
check(#ev == 1 and ev[1].kind == "ON" and ev[1].text == "below 30%", "on, and why")
flt.inp[1] = 15
c:update({ main }, at(0.2), 200, src(10))
ev = c:drain()
check(kinds(ev) == "FAULT OFF", "a fault, and the switch going off for it")
flt.inp[1] = 0
c:update({ main }, at(0.2), 210, src(95))
ev = c:drain()
check(kinds(ev) == "CLEAR TRIP", "the fault gone; then a heat trip")
c:setMode("Vac", "off", 220)
c:reset("Vac", 230)
check(kinds(c:drain()) == "HAND RESET", "a mode set by hand, a reset")

---------------------------------------------------------------- the page, in lumen
local CAP = 2e10
local lsc = LSC.new{ stored = 0.6 * CAP, capacity = CAP, inSec = 0, outSec = 60000, in1h = 60000, out1h = 60000 }
local rsK, reactors = {}, {}
M.components = { ["d2440f27-52c9"] = lsc.entry }
for k = 1, 3 do
  rsK[k] = Gen.redstone()
  reactors[k] = Gen.reactor{ heat = 1000, maxHeat = 10000, output = 43600, produces = false }
  M.components[("c%03d0000-0000"):format(k)] = rsK[k].entry
  M.components[("e%03d0000-0000"):format(k)] = reactors[k].entry
end
local cfgPath = H.TMP .. "/lumen.cfg"
local fh = assert(io.open(cfgPath, "w"))
fh:write([[return {
  heatWarn = 95, heatBad = 98, glanceAfter = 0,
  sources = { { address = "e001", name = "N-1" }, { address = "e002", name = "N-2" }, { address = "e003", name = "S-6" } },
  groups = { { name = "Quad Uranium", steps = { { onBelow = 75, offAbove = 90, run = 1 } } } },
  control = {
    { name = "Reactor N-1", redstone = "c001", side = "top", group = "Quad Uranium", source = "N-1" },
    { name = "Reactor N-2", redstone = "c002", side = "top", group = "Quad Uranium", source = "N-2" },
    { name = "Reactor S-6", redstone = "c003", side = "top", always = true, source = "S-6" },
  },
}
]])
fh:close()
local function step() for k = 1, 3 do reactors[k].state.produces = (rsK[k].out[1] or 0) > 0 end end
local function run(untilTime, onPull)
  M.pulls = 0
  local quitAt
  M.onPull = function(n)
    step()
    local e = onPull and onPull(n, M.time)
    if e then return e end
    if M.time >= untilTime then
      if not quitAt then quitAt = n; return { "touch", "scr", M.W - 3, 1, 0, "Alex" } end
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
local function tapAt(text, minY, minX, who)
  local x, y = M.find(text, minY, minX)
  assert(x, "nothing to tap: " .. text)
  return { "touch", "scr", x + 1, y, 0, who or "Steve" }
end

-- A day already kept (as lumen.state and lumen.log keep it): N-1 and N-2 taking turns, S-6 always on but for a
-- fault and an hour set OFF by hand, a heat trip on N-2 and its RESET.
M.setTime(0)
do
  local NOW = M.epoch
  local day = history.new()
  local events = log.new(H.TMP .. "/lumen-log.cfg", NOW)
  local tot = { name = "LSC d244", address = "d2440f27-52c9", ok = true, stored = 1.2e10 }
  for t = NOW - 86400 + 30, NOW - 60, 30 do
    tot.fill = 0.72 + 0.12 * math.sin((t - NOW) / 86400 * 4 * math.pi)
    day:add(tot.address, tot, t, 30)
  end
  local function hoursIn(hrs) return NOW - 86400 + hrs * 3600 end
  for k = 0, 7 do
    day:state("Reactor N-1", k % 2 == 0 and "on" or "off", hoursIn(k * 3))
    day:state("Reactor N-2", k % 2 == 0 and "off" or "on", hoursIn(k * 3))
    events:add(hoursIn(k * 3), "ON", k % 2 == 0 and "Reactor N-1" or "Reactor N-2", "starting: 1 of 2 needed")
    events:add(hoursIn(k * 3), "OFF", k % 2 == 0 and "Reactor N-2" or "Reactor N-1", "stopping: 1 of 2 needed")
  end
  day:state("Reactor N-2", "trip", hoursIn(16))
  events:add(hoursIn(16), "TRIP", "Reactor N-2", "heat 91%, trips at 90%")
  day:state("Reactor N-2", "off", hoursIn(16.5))
  events:add(hoursIn(16.5), "RESET", "Reactor N-2", "heat trip reset (heat 91%, trips at 90%)", "Steve")
  day:state("Reactor S-6", "on", hoursIn(0))
  day:state("Reactor S-6", "fault", hoursIn(9))
  events:add(hoursIn(9), "FAULT", "Reactor S-6", "fault signal")
  day:state("Reactor S-6", "on", hoursIn(9.4))
  events:add(hoursIn(9.4), "CLEAR", "Reactor S-6", "fault gone")
  day:state("Reactor S-6", "handoff", hoursIn(20))
  events:add(hoursIn(20), "HAND", "Reactor S-6", "set OFF (was AUTO)", "Alex")
  day:state("Reactor S-6", "on", hoursIn(21))
  events:add(hoursIn(21), "HAND", "Reactor S-6", "set AUTO (was OFF)", "Alex")
  events:add(hoursIn(22), "WARN", "alert", "LSC d244 low: 24.8%")
  events:add(hoursIn(22.4), "GONE", "alert", "LSC d244 low: 24.8%")
  for _, name in ipairs({ "Reactor N-1", "Reactor N-2", "Reactor S-6" }) do day:state(name, "gone", NOW - 60) end
  require("lumen.state").save(H.TMP .. "/lumen-state.cfg", { saved = NOW, history = day:save() })
end

M.resize(160, 50)
M.aspect = { 7, 3 }
run(300, function(n)
  if n == 20 then
    local _, y = M.find("Reactor S-6", 3)
    return tapAt(" OFF ", y, 120, "Steve")            -- three switches: rows, its buttons on its line
  end
end)
local seen = {}
run(M.time + 60, function(n)
  if n == 2 then return tapAt(" TIMELINE ", 3) end
  if n == 4 then
    seen.page = M.find("◀ BACK", 3) and M.find("TIMELINE", 3) and M.find(" 24 H ", 3) and M.find("running", 5)
      and M.find("Reactor N-1", 8) and M.find("Reactor S-6", 8) and M.find("off by hand", 8)
    seen.events = M.find("Steve: set OFF (was AUTO)", 8) and M.find("started (v", 8) and M.find("QUIT on the screen", 8)
      and M.find("starting: 1 of 2 needed", 8)
    seen.oob = M.oob
    H.screen("lumen-timeline")
  end
  if n == 5 then return tapAt(" BY HAND ", 3) end
  if n == 7 then seen.hand = M.find("Steve: set OFF", 8) and not M.find("started (v", 8) end
  if n == 8 then return tapAt(" 7 D ", 3) end
  if n == 10 then seen.week = M.find("-7d", 5) and M.find("the fill's kept for 24 hours", 5) end
end)
check(seen.page, "TIMELINE: the fill, how many ran, a bar per switch, the legend")
check(seen.events, "events: who tapped what, the reasons switches switched, LUMEN starting and quitting, across a restart")
check(seen.oob == 0, "fits the 7 x 3 wall")
check(seen.hand, "BY HAND: only what someone tapped")
check(seen.week, "7 D: a week of bars (the fill's only kept for a day)")
local kept = log.new(H.TMP .. "/lumen-log.cfg", M.epoch + M.time)
local quits = 0
for _, e in ipairs(kept.list) do if e.kind == "STOP" and e.player == "Alex" then quits = quits + 1 end end
check(quits == 2, "QUIT on the screen, with who tapped it, logged each time")
check(#kept.list > 30, "the day kept before is still there")

M.aspect = nil
M.resize(80, 25)
M.oob = 0
seen = {}
run(M.time + 20, function(n)
  if n == 2 then return tapAt(" TIMELINE ", 3) end
  if n == 4 then
    seen.fits = M.oob == 0 and M.find("Reactor S-6", 8) and M.find("EVENTS", 8)
    H.screen("lumen-timeline-tier2")
  end
end)
check(seen.fits, "tier 2: fits, bars and events")
M.resize(160, 50)

H.done()
