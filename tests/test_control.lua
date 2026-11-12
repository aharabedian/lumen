-- test_control.lua: switching generators by fill (lumen.control: redstone and GT machines, the marks, waiting
-- between switches, holding when the fill can't be read, manual modes), reading sources (lumen.sources: GT
-- generators, IC2 reactors), and alerts that don't cry wolf with them (lumen.alerts: standby, draining with
-- the generators on, sources and switches), plus their settings (lumen.config).
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local Gen = require("gen")
local check = H.check
local component = require("component")
local config = require("lumen.config")
local control = require("lumen.control")
local sources = require("lumen.sources")
local alerts = require("lumen.alerts")

local function bad(t, text)
  local c, err = config.check(t)
  return c == nil and err and err:find(text, 1, true) ~= nil
end

---------------------------------------------------------------- settings
local ok = config.check({ control = { { name = "Vac nuke", redstone = "5e1f", side = "north", onBelow = 30, offAbove = 90 } },
  sources = { { address = "a1b2", name = "LFTR", alwaysOn = true } } })
check(ok and ok.heatWarn == 25 and ok.heatBad == 50 and ok.inputDrop == nil, "a switch and a source; heat and input defaults")
check(bad({ control = { { name = "x", onBelow = 30, offAbove = 90 } } }, "needs redstone"), "a switch needs redstone or machine")
check(bad({ control = { { name = "x", redstone = "a", machine = "b", side = 1, onBelow = 30, offAbove = 90 } } }, "one of them"),
  "not both")
check(bad({ control = { { name = "x", redstone = "a", side = "sideways", onBelow = 30, offAbove = 90 } } }, "side must be"),
  "a side LUMEN doesn't know is refused")
check(bad({ control = { { name = "x", redstone = "a", side = 2, onBelow = 90, offAbove = 30 } } }, "onBelow must be below offAbove"),
  "the marks must leave a gap")
check(bad({ control = { { name = "x", machine = "a", onBelow = 30, offAbove = 90 }, { name = "x", machine = "b",
  onBelow = 30, offAbove = 90 } } }, "two switches have that name"), "names are unique")
check(bad({ sources = { { address = "a1" } } }, "needs an address"), "a source needs a name")
check(bad({ heatWarn = 60, heatBad = 50 }, "heatWarn must not be above heatBad"), "heat marks in order")
check(bad({ inputDrop = 0 }, "inputDrop must be"), "inputDrop is a percent")

---------------------------------------------------------------- switching with redstone
local rs = Gen.redstone()
M.components = { ["5e1f0000-0000"] = rs.entry }
local cfg = config.check({ control = { { name = "Vac nuke", redstone = "5e1f", side = "north", onBelow = 30, offAbove = 90 } } })
local function at(fill) return { name = "All LSCs", address = "", ok = true, fill = fill, stored = fill * 1e10 } end
local main = { name = "Main", address = "d244", ok = true }

rs.out[2] = 15
local c = control.new(component, cfg)
c:update({ main }, at(0.6), 0)
local s = c.list[1]
check(s.on == true and s.mode == "auto" and rs.sets == 0 and s.since == 0, "on start, the output as it is: on, nothing set")
c:update({ main }, at(0.95), 100)
check(s.on == false and rs.out[2] == 0 and s.since == 100 and s.why == "above 90%", "above offAbove: off (north is side 2)")
c:update({ main }, at(0.5), 200)
check(s.on == false and rs.sets == 1, "between the marks: stays off")
c:update({ main }, at(0.29), 300)
check(s.on == true and rs.out[2] == 15 and s.why == "below 30%", "below onBelow: on, at full strength")
c:update({ main }, at(0.95), 330)
check(s.on == true and s.why == "waiting to switch again", "waits a minute after a switch before switching again")
c:update({ main }, at(0.95), 360)
check(s.on == false, "then switches")
c:update({ main }, { name = "All LSCs", address = "", ok = false }, 500)
check(s.on == false and s.fill == nil and s.why:find("holding", 1, true), "can't read the fill: holds")
rs.out[2] = 15                                  -- the chunk reloaded with the output on, or someone changed it
c:update({ main }, at(0.5), 600)
check(rs.out[2] == 0 and s.on == false, "an output that doesn't match is set again")

c:setMode("Vac nuke", "on", 610)
check(s.mode == "on" and s.on == true and rs.out[2] == 15 and s.since == 610, "ON on the screen: on at once")
c:update({ main }, at(0.99), 700)
check(s.on == true and s.why:find("ON", 1, true), "by hand, the fill doesn't matter")
check(c:modes()["Vac nuke"] == "on", "manual modes are kept")
local c2 = control.new(component, cfg, { ["Vac nuke"] = "on" })
check(c2.list[1].mode == "on", "and come back after a restart")
c:setMode("Vac nuke", "auto", 710)
check(s.on == false and c:modes()["Vac nuke"] == nil, "AUTO: follows the fill again, at once")

-- invert: the signal means "stop" (an SFM line that runs while it sees no signal).
cfg = config.check({ control = { { name = "Inv", redstone = "5e1f", side = 3, invert = true, strength = 7, onBelow = 30,
  offAbove = 90 } } })
rs.out[3] = 0
c = control.new(component, cfg)
c:update({ main }, at(0.95), 0)
check(rs.out[3] == 7 and c.list[1].on == false, "invert: off is a signal (strength 7)")
c:update({ main }, at(0.1), 100)
check(rs.out[3] == 0 and c.list[1].on == true, "invert: on is no signal")

rs.broken = "unloaded"
c:update({ main }, at(0.1), 200)
check(c.list[1].err == "unloaded" and c.list[1].on == nil, "a redstone component that fails: the error, state unknown")
rs.broken = nil
M.components = {}
c = control.new(component, cfg)
c:update({ main }, at(0.1), 0)
check(c.list[1].err:find("no redstone component at 5e1f", 1, true), "a redstone component that isn't there says so")

---------------------------------------------------------------- switching a GT machine, following one LSC
local lftr = Gen.gt("gtpp.multimachine.lftr", { active = true })
local lsc = LSC.new{ stored = 1, capacity = 10 }
M.components = { ["a1b20000-0000"] = lftr.entry, ["d2440000-0000"] = lsc.entry }
cfg = config.check({ control = { { name = "LFTR", machine = "a1b2", lsc = "Main", onBelow = 50, offAbove = 95 },
  { name = "Oops", machine = "d244", onBelow = 50, offAbove = 95 } } })
c = control.new(component, cfg)
c:update({ { name = "Main", address = "x", ok = true, fill = 0.97 }, { name = "Other", address = "y", ok = true, fill = 0.1 } },
  at(0.5), 0)
check(lftr.allowed == false and c.list[1].on == false and c.list[1].fill == 0.97, "a GT machine: setWorkAllowed, following its LSC")
check(c.list[2].err and c.list[2].err:find("LSC", 1, true) and (lsc.calls.setWorkAllowed or 0) == 0, "an LSC is never switched")

---------------------------------------------------------------- sources
local P = "gt5u.multiblock."
local gen = Gen.gt("gtpp.multimachine.lftr", { active = true, progress = 30, max = 120,
  lines = { "§aProgress:§r 30 / 120", "Problems: §c0§r Efficiency: §e100.0§r %", "Current Output: §a12,288§r EU/t" } })
local reactor = Gen.reactor{ heat = 2600, maxHeat = 10000, output = 1600, produces = true }
local chamber = Gen.reactor{ heat = 0, maxHeat = 10000, output = 0, produces = false }
chamber.entry.type = "reactor_chamber"
M.components = { ["a1b20000-0000"] = gen.entry, ["eeee0000-0000"] = reactor.entry, ["cccc0000-0000"] = chamber.entry }
cfg = config.check({ sources = { { address = "a1b2", name = "LFTR", alwaysOn = true }, { address = "eeee", name = "Vac nuke" },
  { address = "9999", name = "Gone" } } })
local list = sources.new(component, cfg):read()
check(#list == 4 and list[1].name == "LFTR" and list[2].name == "Vac nuke" and list[3].name == "Gone"
  and list[4].name == "Reactor cccc", "configured sources in order, then reactors found by themselves")
local l1 = list[1]
check(l1.ok and l1.kind == "gt" and l1.active and l1.output == 12288 and l1.problems == 0 and math.abs(l1.progress - 0.25) < 1e-9,
  "a GT generator: running, output and problems from its lines, recipe progress")
local l2 = list[2]
check(l2.ok and l2.kind == "reactor" and l2.active and l2.output == 1600 and math.abs(l2.heat - 0.26) < 1e-9,
  "an IC2 reactor: producing, EU/t, heat")
check(list[3].ok == false and list[3].err:find("nothing found", 1, true), "a source that isn't there says so")
local g = sources.gtLines({ P .. "problems\\\\3", "kekztech.infodata.multi.maintenance_status.ok" })
check(g.problems == 3, "problems as a key and a number")
check(sources.gtLines({ "kekztech.infodata.multi.maintenance_status.needs_work" }).problems == 1, "kekztech's maintenance line")
check(sources.gtLines({ "Stored Energy: 5 EU" }).output == nil, "no output line: no output (not a guess)")

---------------------------------------------------------------- alerts with switches and sources
cfg = config.check({ inputDrop = 50 })
local function ids(l)
  local out = {}
  for _, a in ipairs(l) do out[#out + 1] = a.level .. " " .. a.id end
  return table.concat(out, ", ")
end
-- The vacuum reactor's off cycle: LUMEN switched it off at 90%; the hour's net says empty in 2 hours.
local r = { name = "Main", address = "d244", ok = true, fill = 0.8, stored = 8e9, capacity = 1e10,
  drain = { ["1h"] = 7200 }, in5m = 0, in1h = 60000 }
local off = { name = "Vac nuke", mode = "auto", on = false, since = 0, onBelow = 30, offAbove = 90, source = "Vac nuke" }
local ctx = { now = 3000, switches = { off }, sources = {}, rate = function() return -5000 end }
check(select(2, alerts.drain(r, cfg, ctx)) == "standby" and #alerts.evaluate({ r }, cfg, ctx) == 0,
  "generators off by LUMEN: draining is standby, no drain alert, no input alert")
check(ids(alerts.evaluate({ r }, cfg, { now = 3000 })) == "warn drain:d244, warn input:d244",
  "the same LSC without switches: the hour's net raises it (what used to happen every off cycle)")

local on = { name = "Vac nuke", mode = "auto", on = true, since = 2700, onBelow = 30, offAbove = 90 }
ctx = { now = 3000, switches = { on }, sources = {}, rate = function() return -100000 end }
check(alerts.drain(r, cfg, ctx) == nil and select(2, alerts.drain(r, cfg, ctx)) == "settling",
  "just switched on: no judgement for 10 minutes")
ctx.now = 3400
local seen
ctx.rate = function(_, seconds) seen = seconds; return -100000 end
local secs, how = alerts.drain(r, cfg, ctx)
check(math.abs(secs - 8e9 / 100000 / 20) < 1e-6 and how == "draining with Vac nuke on" and seen == 700,
  "on for 10 minutes and still draining: time to empty at the rate since it came on")
local list2 = alerts.evaluate({ r }, cfg, ctx)
check(#list2 == 1 and list2[1].id == "drain:d244" and list2[1].level == "warn" and list2[1].hold == 300
  and list2[1].text == "Main empty in 1h 06m (draining with Vac nuke on)", "...a drain alert, held 5 minutes; no input alert (switched within the hour)")
ctx.rate = function() return 2000 end
check(select(2, alerts.drain(r, cfg, ctx)) == "keeping up", "on and filling: keeping up")
local manual = { name = "Vac nuke", mode = "off", on = false, since = 0, onBelow = 30, offAbove = 90 }
ctx = { now = 9000, switches = { manual }, sources = {} }
check(alerts.drain(r, cfg, ctx) == 7200, "switched OFF by hand: drain alerts as without switches (nothing will save it)")
local other = { name = "Other", mode = "auto", on = false, lsc = "Spare", since = 0, onBelow = 30, offAbove = 90 }
check(alerts.drain(r, cfg, { now = 9000, switches = { other } }) == 7200, "a switch following another LSC doesn't count")

-- Sources and switches.
local srcs = {
  { name = "Vac nuke", kind = "reactor", ok = true, active = false, heat = 0.6 },
  { name = "LFTR", kind = "gt", ok = true, active = false, problems = 2, alwaysOn = true },
  { name = "Gone", ok = false, err = "nothing found at 9999" },
}
local sw = { name = "Vac nuke", mode = "auto", on = true, since = 0, source = "Vac nuke" }
local broken = { name = "Pump", err = "no redstone component at 5e1f" }
list2 = alerts.evaluate({}, cfg, { now = 100, switches = { sw, broken }, sources = srcs })
check(ids(list2) == "bad heat:Vac nuke, bad switch:Pump, warn none, warn problems:LFTR, warn running:Vac nuke, "
  .. "warn source:Gone, warn stopped:LFTR", "heat, a broken switch, maintenance, switched on but not running, unreadable, stopped")
srcs[1].heat, srcs[1].active = 0.3, true
sw.on = false
list2 = alerts.evaluate({}, cfg, { now = 100, switches = { sw }, sources = srcs })
check(ids(list2):find("warn heat:Vac nuke", 1, true) and ids(list2):find("warn running:Vac nuke", 1, true)
  and list2[#list2].text ~= nil, "heat over heatWarn: warn; switched off but still running: warn")
local lftrSw = { name = "LFTR", mode = "auto", on = false, since = 0, source = "LFTR" }
list2 = alerts.evaluate({}, cfg, { now = 100, switches = { lftrSw }, sources = { srcs[2] } })
check(not ids(list2):find("stopped", 1, true), "an alwaysOn source its switch turned off isn't 'stopped'")

H.done()
