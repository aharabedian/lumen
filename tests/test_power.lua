-- test_power.lua: finding and reading LSCs (lumen.power), the alerts they raise (lumen.alerts), and the
-- settings that drive both (lumen.config).
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local check = H.check
local component = require("component")
local config = require("lumen.config")
local power = require("lumen.power")
local alerts = require("lumen.alerts")

---------------------------------------------------------------- config
local cfg = config.load(H.TMP .. "/none.cfg")
check(cfg.missing and cfg.interval == 5 and cfg.lowFill == 25 and cfg.lensPort == nil and cfg.lensNode == "lumen",
  "no config file: every default")
local function bad(t, text)
  local c, err = config.check(t)
  return c == nil and err and err:find(text, 1, true) ~= nil
end
check(bad({ lowFill = 120 }, "lowFill must be a percent"), "a fill over 100% is refused")
check(bad({ lowFill = 5, criticalFill = 10 }, "criticalFill must not be above lowFill"), "critical above low is refused")
check(bad({ names = { d244 = 3 } }, "names:"), "a name must be text")
check(bad({ resolution = { 20, 5 } }, "resolution must be"), "a tiny resolution is refused")
check(bad({ lensPort = 70000 }, "lensPort must be"), "a port out of range is refused")
local f = io.open(H.TMP .. "/broken.cfg", "w"); f:write("return { interval = }"); f:close()
local c, err = config.load(H.TMP .. "/broken.cfg")
check(c == nil and err:find("broken.cfg", 1, true), "a file that doesn't parse says where")
local ex, exErr = config.load(H.ROOT .. "/config/lumen.example.cfg")
check(ex and not ex.missing, "config/lumen.example.cfg loads" .. (ex and "" or ": " .. tostring(exErr)))

---------------------------------------------------------------- reading
local main = LSC.new{ stored = 10773450724, capacity = 11340000000, inSec = 65536, outSec = 64716,
  in5m = 66082, out5m = 65712, in1h = 42420, out1h = 42338, timeTo = "full", timeText = "10.42 hours" }
local spare = LSC.new{ stored = 1e9, capacity = 4e9, inSec = 0, outSec = 2000, timeTo = "empty", timeText = "3.47 hours" }
M.components = {
  ["d2440f27-52c9"] = main.entry,
  ["0aaa1111-0000"] = spare.entry,
  ["ebf00000-0000"] = LSC.machine("multimachine.electricblastfurnace"),
}
cfg = config.check({ names = { d2440f27 = "Main" } })
local p = power.new(component, cfg)
local r = p:read()
check(#r == 2 and r[1].name == "LSC 0aaa" and r[2].name == "Main", "only LSCs, named from cfg.names or their address, sorted")
local m1 = r[2]
check(m1.ok and m1.stored == 10773450724 and m1.capacity == 11340000000 and math.abs(m1.fill - 0.95003) < 1e-4,
  "stored, capacity and fill from the LSC's own lines")
check(m1.inEut == 65536 and m1.outEut == 64716 and m1.net == 820 and m1.net5m == 370 and m1.net1h == 82,
  "flows: the LSC's 5 s averages, and net over 5 s, 5 min, 1 h")
check(math.abs(m1.full - 37512) < 1e-6 and m1.empty == nil and m1.timeText == "10.42 hours", "time to full: the LSC's own")
check(r[1].empty and math.abs(r[1].empty - 3.47 * 3600) < 1e-6, "time to empty: the LSC's own")
check(m1.maintenance == "ok" and m1.passiveLoss == 65, "maintenance, passive loss")
check((main.calls.setWorkAllowed or 0) == 0, "nothing that changes the game is called")
p:read()
check(main.calls.getName == 1, "each machine is asked its name once")

local t = power.total(r)
check(t.name == "All LSCs" and t.stored == 10773450724 + 1e9 and t.capacity == 15340000000 and t.net == 820 - 2000,
  "the total adds up the LSCs")
check(t.empty and math.abs(t.empty - (t.stored / (370 - 2000 + 0 - 0) / -20)) < 1, "the total's time to empty, from net over 5 min")
check(power.total({ r[1] }) == nil, "no total for a single LSC")

-- An LSC whose own lines don't say how long: worked out from the 5 min net.
spare.state.timeTo = nil
r = p:read()
check(math.abs(r[1].empty - 1e9 / 2000 / 20) < 1e-6, "no time line: time to empty worked out from net over 5 min")

spare.state.broken = "chunk unloaded"
r = p:read()
check(r[1].ok == false and r[1].err:find("chunk unloaded", 1, true) and r[2].ok, "an LSC that can't be read says why; the others still read")
t = power.total(r)
check(t.stored == 10773450724, "the total counts only what could be read")
spare.state.broken = nil

check(power.duration(37512) == "10h 25m" and power.duration(90) == "1m" and power.duration(5) == "5s"
  and power.duration(3 * 86400 + 7200) == "3d 2h", "durations read naturally")

---------------------------------------------------------------- alerts
cfg = config.check({ names = { d2440f27 = "Main" } })
local function ids(list)
  local out = {}
  for _, a in ipairs(list) do out[#out + 1] = a.level .. " " .. a.id end
  return table.concat(out, ", ")
end
check(#alerts.evaluate(power.new(component, cfg):read(), cfg) == 0, "healthy LSCs (25% and 6.9 h left is fine) raise nothing")
local list = alerts.evaluate({}, cfg)
check(ids(list) == "warn none", "no LSC found: a warning")

local function one(state)
  local l = LSC.new(state)
  M.components = { ["d2440f27-52c9"] = l.entry }
  return alerts.evaluate(power.new(component, cfg):read(), cfg)
end
check(ids(one{ stored = 2e9, capacity = 1e10, inSec = 10, outSec = 10 }) == "warn fill:d2440f27-52c9", "below lowFill: warn")
list = one{ stored = 5e8, capacity = 1e10, inSec = 10, outSec = 10 }
check(ids(list) == "bad fill:d2440f27-52c9" and list[1].text == "Main nearly empty: 5.0%", "below criticalFill: bad, with the name")
check(ids(one{ stored = 9e9, capacity = 1e10, outSec = 100, timeTo = "empty", timeText = "3 hours" })
  == "warn drain:d2440f27-52c9", "empty within drainWarnHours: warn")
list = one{ stored = 9e9, capacity = 1e10, outSec = 100, timeTo = "empty", timeText = "30 minutes" }
check(ids(list) == "bad drain:d2440f27-52c9" and list[1].text == "Main empty in 30m", "empty within drainBadHours: bad")
check(#one{ stored = 9e9, capacity = 1e10, outSec = 100, timeTo = "empty", timeText = "5 hours" } == 0, "empty later: fine")
check(ids(one{ stored = 9e9, capacity = 1e10, maintenance = "needs_work" }) == "warn maint:d2440f27-52c9",
  "maintenance needed: warn")
check(ids(one{ stored = 9e9, capacity = 1e10, broken = "boom" }) == "bad offline:d2440f27-52c9", "can't be read: bad")
list = one{ stored = 1e8, capacity = 1e10, outSec = 100, timeTo = "empty", timeText = "20 minutes", maintenance = "x" }
check(list[1].level == "bad" and list[#list].level == "warn", "bad alerts first")

local tr = alerts.tracker()
local new = tr:update({ { id = "a", level = "warn", text = "" } }, 10)
check(#new == 1 and tr.list[1].since == 10, "a new alert starts now")
new = tr:update({ { id = "a", level = "warn", text = "" } }, 20)
check(#new == 0 and tr.list[1].since == 10, "a continuing one keeps its start")
new = tr:update({ { id = "a", level = "bad", text = "" } }, 30)
check(#new == 1 and new[1] == "a" and tr.list[1].since == 10, "warn to bad counts as new (to beep), same start")
tr:update({}, 40)
new = tr:update({ { id = "a", level = "warn", text = "" } }, 50)
check(#new == 1 and tr.list[1].since == 50, "one that cleared and came back starts again")
check(alerts.health({}) == "ok" and alerts.health({ { level = "warn" } }) == "warn"
  and alerts.health({ { level = "warn" }, { level = "bad" } }) == "bad", "health: the worst level")

H.done()
