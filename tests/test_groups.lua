-- test_groups.lua: reactor fleets in lumen.control. Heat trips (a reactor's heat or how fast it climbs switches
-- it off and latches until RESET; after RESET it may run to cool down), groups (a ladder of steps sets how many
-- members run; the least run time starts first; faulted, tripped and hand-set members are skipped; minSwitch per
-- member), what's kept across a restart, and the alerts that go with them; plus their settings (lumen.config).
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local Gen = require("gen")
local check = H.check
local component = require("component")
local config = require("lumen.config")
local control = require("lumen.control")
local alerts = require("lumen.alerts")

local function bad(t, text)
  local c, err = config.check(t)
  return c == nil and err and err:find(text, 1, true) ~= nil, err
end
local function sw(name, extra)
  local s = { name = name, redstone = "5e1f", side = "north", onBelow = 30, offAbove = 90 }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

---------------------------------------------------------------- settings
local STEPS = { { onBelow = 90, offAbove = 95, run = 2 }, { onBelow = 75, offAbove = 85, run = 2 } }
local ok = config.check({ groups = { { name = "Fleet", steps = STEPS } },
  control = { { name = "R1", redstone = "c001", side = "north", group = "Fleet" } } })
check(ok and ok.groups[1].rotate == true and ok.control[1].onBelow == nil, "a group; a member needs no marks; rotate by default")
check(bad({ control = { { name = "R1", redstone = "c001", side = "north" } } }, "onBelow must be a percent"),
  "a switch outside a group still needs its marks")
check(bad({ control = { sw("R1", { group = "Nope" }) } }, 'group "Nope" isn\'t in groups'), "a member's group must exist")
check(bad({ groups = { { name = "G", steps = {} } } }, "needs steps"), "a group needs steps")
check(bad({ groups = { { name = "G", steps = { { onBelow = 80, offAbove = 70, run = 1 } } } } }, "onBelow must be below offAbove"),
  "a step's marks leave a gap")
check(bad({ groups = { { name = "G", steps = { { onBelow = 70, offAbove = 80, run = 0 } } } } }, "run must be a whole number, 1 or more"),
  "a step runs at least one")
check(bad({ groups = { { name = "G", steps = STEPS }, { name = "G", steps = STEPS } } }, "two groups have that name"),
  "group names are unique")
check(bad({ control = { sw("R1", { heatTrip = 0 }) } }, "heatTrip must be a percent, 1-100"), "heatTrip is a percent")
check(bad({ control = { sw("R1", { heatRise = -2 }) } }, "heatRise must be"), "heatRise is a positive % a minute")
ok = config.check({ control = { { name = "Breeder", redstone = "c001", side = "north", always = true } } })
check(ok and ok.control[1].onBelow == nil, "always on: no marks needed")
check(bad({ groups = { { name = "G", steps = STEPS } }, control = { { name = "B", redstone = "c001", side = "north", always = true,
  group = "G" } } }, "always or group, not both"), "always and a group don't mix")

---------------------------------------------------------------- heat trip
local out = Gen.redstone()
local reactor = Gen.reactor{ heat = 5000, maxHeat = 10000, output = 44000, produces = true }
M.components = { ["5e1f0000-0000"] = out.entry }
local cfg = config.check({ control = { sw("Hot", { source = "Hot reactor", heatTrip = 90, heatRise = 6 }) } })
local function at(fill) return { name = "All LSCs", address = "", ok = true, fill = fill, stored = fill * 1e10 } end
local main = { name = "Main", address = "d244", ok = true }
local function src(heatPct, okRead)
  reactor.state.heat = heatPct * 100
  return { { name = "Hot reactor", kind = "reactor", ok = okRead ~= false, heat = heatPct / 100, active = true,
    err = okRead == false and "unloaded" or nil } }
end

out.out[2] = 15
local c = control.new(component, cfg)
c:update({ main }, at(0.2), 0, { sources = src(50) })
local s = c.list[1]
check(s.on == true and s.trip and not s.trip.on and s.trip.heat == 50, "below the trip: runs; the heat is known")
c:update({ main }, at(0.2), 10, { sources = src(91) })
check(s.trip.on and s.on == false and out.out[2] == 0 and s.why == "heat trip", "at the trip mark: off at once")
check(s.trip.why == "heat 91%, trips at 90%" and s.trip.since == 10, "and why")
c:setMode("Hot", "on", 20)
check(s.on == false and out.out[2] == 0, "ON by hand doesn't override a trip")
c:setMode("Hot", "auto", 21)
c:update({ main }, at(0.2), 30, { sources = src(80) })
check(s.trip.on and s.on == false, "latched: the heat falling doesn't clear it")
check(c:trips().Hot == "heat 91%, trips at 90%", "a trip is kept across restarts")
local c2 = control.new(component, cfg, { trips = c:trips() })
c2:update({ main }, at(0.2), 0, { sources = src(80) })
check(c2.list[1].trip.on and c2.list[1].trip.since == 0 and c2.list[1].on == false, "and comes back tripped")

-- RESET while still over the mark: it may run to cool down, tripping again 5 points higher.
c:update({ main }, at(0.2), 40, { sources = src(92) })
c:reset("Hot", 100)
check(not s.trip.on and s.trip.rearm == 97 and s.on == true and out.out[2] == 15, "RESET at 92%: runs again; trips at 97% until it cools")
check(type(c:trips().Hot) == "table" and c:trips().Hot.rearm == 97, "the raised mark is kept across restarts")
c2 = control.new(component, cfg, { trips = c:trips() })
c2:update({ main }, at(0.2), 0, { sources = src(92) })
check(not c2.list[1].trip.on and c2.list[1].trip.rearm == 97, "so a restart at 92% doesn't trip it again")
c:update({ main }, at(0.2), 110, { sources = src(95) })
check(not s.trip.on and s.on == true, "95%: under the raised mark, still running")
c:update({ main }, at(0.2), 120, { sources = src(88) })
check(s.trip.rearm == nil, "cooled below 90%: back to the usual mark")
c:update({ main }, at(0.2), 130, { sources = src(90) })
check(s.trip.on, "and 90% trips it again")
c:reset("Hot", 200)
c:update({ main }, at(0.2), 205, { sources = src(94) })
c:update({ main }, at(0.2), 210, { sources = src(98) })
check(s.trip.on and s.trip.why == "heat 98%, trips at 95%", "the raised mark trips too")

-- How fast it climbs: judged over at least 30 s.
c:reset("Hot", 300)
c:update({ main }, at(0.2), 300, { sources = src(50) })
c:update({ main }, at(0.2), 310, { sources = src(52) })
c:update({ main }, at(0.2), 320, { sources = src(54) })
check(not s.trip.on, "20 s of climbing: not judged yet")
c:update({ main }, at(0.2), 330, { sources = src(56) })
check(s.trip.on and s.trip.why == "heat rising 12.0% a minute, trips at 6%", "12% a minute over 30 s: tripped")
c:reset("Hot", 400)
for k = 0, 12 do c:update({ main }, at(0.2), 400 + k * 10, { sources = src(50 + k * 0.5) }) end
check(not s.trip.on and s.on == true, "3% a minute: runs")
c:update({ main }, at(0.2), 600, { sources = src(99, false) })
check(not s.trip.on and s.trip.heat == nil, "a source that can't be read trips nothing (its own alert says so)")

c:update({ main }, at(0.2), 610, { sources = src(91) })
local list = alerts.evaluate({ main }, config.check({}), { now = 700, switches = c.list, sources = {} })
local trip
for _, a in ipairs(list) do if a.id == "trip:Hot" then trip = a end end
check(trip and trip.level == "bad" and trip.hold == 0 and trip.text == "Hot: heat trip (heat 91%, trips at 90%), switched off",
  "a trip is a bad alert at once")
local drainR = { name = "Main", address = "d244", ok = true, stored = 1e9, fill = 0.2, drain = { ["1h"] = 3600 } }
local secs, how = alerts.drain(drainR, config.check({}), { now = 700, switches = c.list })
check(secs == 3600 and how == "1 h average", "a tripped switch isn't standby: draining is real")

---------------------------------------------------------------- always on
-- A breeder that should always run: on unless OFF on the screen, a fault or a heat trip.
local brs, bflt = Gen.redstone(), Gen.redstone()
M.components = { ["b0010000-0000"] = brs.entry, ["b0020000-0000"] = bflt.entry }
local bcfg = config.check({ control = { { name = "Breeder", redstone = "b001", side = "north", always = true, source = "Breeder reactor",
  heatTrip = 75, fault = { redstone = "b002", side = "top" } } } })
local function bsrc(pct) return { sources = { { name = "Breeder reactor", ok = true, heat = pct / 100, active = true } } } end
c = control.new(component, bcfg)
c:update({ main }, at(0.99), 0, bsrc(40))
s = c.list[1]
check(s.always and s.on == true and (brs.out[2] or 0) == 15 and s.why == "always on", "always: on, at 99% full too")
c:update({ main }, nil, 10, bsrc(40))
check(s.on == true, "and while the fill can't be read")
c:setMode("Breeder", "off", 20)
check(s.on == false and (brs.out[2] or 0) == 0, "OFF on the screen: off")
c:setMode("Breeder", "auto", 30)
check(s.on == true, "ON (auto): on again at once")
bflt.inp[1] = 15
c:update({ main }, at(0.5), 100, bsrc(40))
check(s.on == false and s.why == "fault: stopped", "a fault stops it")
bflt.inp[1] = 0
c:update({ main }, at(0.5), 110, bsrc(40))
check(s.on == false and s.why == "waiting to switch again", "the fault gone: it waits its minute")
c:update({ main }, at(0.5), 170, bsrc(40))
check(s.on == true, "then runs")
c:update({ main }, at(0.5), 180, bsrc(76))
check(s.trip.on and s.on == false, "a heat trip stops it")

---------------------------------------------------------------- groups
local rs = {}
M.components = {}
local members = {}
for k = 1, 5 do
  rs[k] = Gen.redstone()
  M.components[("c00%d0000-0000"):format(k)] = rs[k].entry
  members[k] = { name = "R" .. k, redstone = ("c00%d"):format(k), side = "north", group = "Fleet" }
end
members[2].fault = { redstone = "c002", side = "south" }
local gcfg = config.check({ groups = { { name = "Fleet", steps = { { onBelow = 90, offAbove = 95, run = 2 },
  { onBelow = 75, offAbove = 85, run = 2 }, { onBelow = 50, offAbove = 65, run = 1 } } } }, control = members })
local HOURS = { R1 = 5 * 3600, R2 = 3600, R3 = 3 * 3600, R4 = 1800, R5 = 2 * 3600 }
local function on() local o = {} for k = 1, 5 do if (rs[k].out[2] or 0) > 0 then o[#o + 1] = "R" .. k end end return table.concat(o, " ") end
local function tick(fill, t) c:update({ main }, fill and at(fill) or { name = "All LSCs", address = "", ok = false }, t, { onTime = HOURS }) end

c = control.new(component, gcfg)
local g = c.groups[1]
tick(0.8, 0)
check(on() == "" and g.need == nil, "the first look: outputs as they are, nothing switched")
tick(0.8, 10)
check(g.need == 2 and on() == "R2 R4", "80%: step 1 (below 90%) runs 2; the least run time first (R4 30m, R2 1h)")
check(g.steps[1].active and g.steps[2].active == false and g.steps[3].active == false, "step 2's band, nothing running: off")
tick(0.7, 100)
check(g.need == 4 and on() == "R2 R3 R4 R5", "below 75%: 4, adding R5 (2h) and R3 (3h)")
tick(0.45, 200)
check(g.need == 5 and on() == "R1 R2 R3 R4 R5", "below 50%: all 5")
tick(0.6, 300)
check(g.need == 5 and on() == "R1 R2 R3 R4 R5", "back in step 3's band: still 5 (off only above 65%)")
tick(0.66, 310)
check(g.need == 4 and on() == "R2 R3 R4 R5", "above 65%: 4; the most run time stops (R1)")
check(g.running == 4 and #g.order == 5 and g.order[1].name == "R4" and g.order[5].name == "R1", "the order: least run time first")

-- A fault on a running member: it stops, and the next in line takes its place once it may switch.
rs[2].inp[3] = 15
tick(0.66, 320)
check(on() == "R3 R4 R5" and c.list[2].why == "fault: stopped", "R2 faults: stopped at once")
check(c.list[1].why == "waiting to switch again", "R1 would replace it, but switched 10 s ago")
tick(0.66, 370)
check(on() == "R1 R3 R4 R5", "a minute after its last switch, R1 replaces R2")
rs[2].inp[3] = 0
tick(0.66, 380)
check(on() == "R1 R3 R4 R5" and c.list[2].why == "standing by: 4 of 5 needed", "the fault gone: R2 stands by")

-- By hand: out of the group until AUTO.
c:setMode("R3", "off", 400)
tick(0.66, 460)
check(on() == "R1 R2 R4 R5" and c.list[3].mode == "off", "R3 OFF by hand: out of the group; R2 takes its place")
c:setMode("R3", "auto", 470)
tick(0.66, 530)
check(g.running == 4 and on() == "R1 R2 R4 R5", "back in AUTO: a member again, standing by")
check(c.list[3].why == "standing by: 4 of 5 needed" and c.list[4].why == "4 of 5 needed", "each member says why")

-- The fill can't be read: the group holds.
tick(nil, 600)
check(on() == "R1 R2 R4 R5" and g.why == "holding: can't read the LSC", "unreadable fill: holds")

-- Kept across a restart: which steps were on. Without them, a restart infers them from what's running.
local kept = c:groupSteps()
check(kept.Fleet[1] == true and kept.Fleet[2] == true and kept.Fleet[3] == false, "the steps are kept")
c = control.new(component, gcfg, { groups = kept })
g = c.groups[1]
tick(0.8, 0)
tick(0.8, 10)
check(g.need == 4 and on() == "R1 R2 R4 R5", "restarted at 80% with the steps kept: nothing flips")
c = control.new(component, gcfg)
g = c.groups[1]
tick(0.8, 0)
tick(0.8, 10)
check(g.need == 4 and on() == "R1 R2 R4 R5", "without them: 4 running in step 2's band means step 2 was on")

-- rotate = false: the order in lumen.cfg.
gcfg.groups[1].rotate = false
for k = 1, 5 do rs[k].out[2] = 0 end
c = control.new(component, gcfg)
tick(0.8, 0)
tick(0.8, 10)
check(on() == "R1 R2", "rotate = false: the first ones in the list start")
gcfg.groups[1].rotate = nil

-- Alerts: a member off because the group doesn't need it is standby, not a drain.
secs, how = alerts.drain(drainR, config.check({}), { now = 20, switches = c.list })
check(secs == nil and how == "standby", "members standing by: draining is expected")

H.done()
