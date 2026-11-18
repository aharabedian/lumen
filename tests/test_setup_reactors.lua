-- test_setup_reactors.lua: lumen-setup's screen for a reactor fleet. ▲ ▼ to order switches, a heat trip, a group
-- with two steps built on the GROUPS tab (ADD EVERY SWITCH), and PAIR: each switch run alone to find its reactor,
-- against wiring with traps (two blocks crossed, one driving nothing, one reactor already running, a fault input
-- on), STOP part-way, every output put back as it was, APPLY, SAVE. Then the same panels on a tier 2 screen.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local Gen = require("gen")
local check = H.check
local config = require("lumen.config")

local function addr(c, k) return ("%s%03d0000-0000"):format(c, k) end
local prefix = H.TMP .. "/root"
local home = prefix .. "/home"
os.execute('mkdir -p "' .. home .. '"')
local realGetenv = os.getenv
os.getenv = function(k) if k == "LUMEN_PREFIX" then return prefix end return realGetenv(k) end -- luacheck: ignore 122
local CFG = home .. "/lumen.cfg"

-- The room: 12 reactors, 12 Redstone I/O blocks. Block k runs reactor WIRED[k] from its top: blocks 2 and 5 are
-- crossed, block 6 runs nothing, reactor 12 runs by itself (another lever). Block 3's output starts on.
local WIRED = { 1, 5, 3, 4, 2, nil, 7, 8, 9, 10, 11, nil }
local main = LSC.new{ stored = 5e9, capacity = 1e10 }
M.components = { ["d2440f27-52c9"] = main.entry }
local rs, reactors = {}, {}
for k = 1, 12 do
  rs[k] = Gen.redstone()
  reactors[k] = Gen.reactor{ heat = 0, maxHeat = 10000, output = 44000, produces = false }
  M.components[addr("c", k)] = rs[k].entry
  M.components[addr("e", k)] = reactors[k].entry
end
M.components["r0010000-0000"] = Gen.radar().entry   -- a Computronics radar, to wake big mode
rs[3].out[1] = 15
rs[4].inp[3] = 15         -- MOX 4's fault input (its block's south side) says trouble
local function world()
  for j = 1, 12 do reactors[j].state.produces = j == 12 end
  for k = 1, 12 do
    if WIRED[k] and (rs[k].out[1] or 0) > 0 then reactors[WIRED[k]].state.produces = true end
  end
end

local lines = {}
for k = 1, 12 do
  lines[#lines + 1] = ('    { name = "MOX %d", redstone = "c%03d", side = "top", onBelow = 30, offAbove = 90%s },'):format(k, k,
    k == 4 and ', fault = { redstone = "c004", side = "south" }' or "")
end
local fh = assert(io.open(CFG, "w"))
fh:write("return {\n  names = { d2440f27 = \"Main\" },\n  control = {\n" .. table.concat(lines, "\n") .. "\n  },\n}\n")
fh:close()

-- Each step runs when lumen-setup waits for an event; it returns an event to deliver, or nil (half a second or
-- a minute passes). waitFor repeats until its condition holds.
local steps
local function at(x, y) return { "touch", "scr", x, y, 0, "p" } end
local function tap(text, minY, minX)
  return function()
    local x, y = M.find(text, minY, minX)
    if not x then
      local rows = {}
      for r = 1, M.H do rows[#rows + 1] = M.row(r) end
      error("nothing to tap: " .. text .. "\n" .. table.concat(rows, "\n"))
    end
    return at(x + 1, y)
  end
end
local function tapField(label, gap, minY)
  return function()
    local x, y = M.find(label, minY or 1)
    assert(x, "no field after " .. label)
    return at(x + gap, y)
  end
end
local function key(char, code) return function() return { "key_down", "kb", char, code, "p" } end end
local function typed(text, erase)
  local out = {}
  for _ = 1, erase or 0 do out[#out + 1] = key(8, 14) end
  for c in text:gmatch(".") do out[#out + 1] = key(c:byte(), 0) end
  out[#out + 1] = key(13, 28)
  return out
end
local function add(list) for _, s in ipairs(list) do steps[#steps + 1] = s end end
local function seen(fn) steps[#steps + 1] = function() fn(); return nil end end
local function waitFor(fn, label)
  local tries = 0
  local w
  w = function()
    tries = tries + 1
    if fn() then return nil end
    assert(tries < 600, "waited too long for " .. label)
    table.insert(steps, 1, w)
    return nil
  end
  steps[#steps + 1] = w
end

local function setup()
  M.pulls = 0
  M.onPull = function()
    world()
    local s = table.remove(steps, 1)
    if s then return s() end
    return { "interrupted" }
  end
  local realPrint = print
  print = function() end -- luacheck: ignore 121
  local ok, err = pcall(H.run, "lumen-setup.lua")
  print = realPrint -- luacheck: ignore 121
  M.onPull = nil
  return ok, err
end

M.resize(160, 50)
M.setTime(0)
local DET, FOOT = 40, 50
local found = {}
steps = {}

---------------------------------------------------------------- order, heat trip
add({ tap(" SWITCHES 12 ", 2), tap("MOX 2 ", 4), tap(" ▲ ", DET) })
seen(function() found.up = M.row(4):find("MOX 2", 1, true) and M.row(5):find("MOX 1", 1, true) end)
add({ tap(" ▼ ", DET) })
seen(function() found.down = M.row(4):find("MOX 1", 1, true) and M.row(5):find("MOX 2", 1, true) end)
add({ tap("MOX 1 ", 4), tap(" ON ", DET + 5), tapField("rising", 8, DET + 5) })
add(typed("5"))
seen(function() found.trip = M.find("at 90 % heat, or rising 5 ", DET + 5) end)

-- MOX 12 is a breeder that always runs: no marks, ON / OFF on the screen.
add({ tap("MOX 12 ", 4), tap("by fill ▸", DET + 1) })
seen(function() found.runsPick = M.find("How MOX 12 runs", 1) and M.find("always", 3) and M.find("by fill", 3) end)
add({ tap("ON / OFF on the screen; faults", 3) })
seen(function() found.always = M.find("always ▸", DET + 1) and M.find("ON / OFF on the screen", DET + 1) and M.find("no fill", DET + 4) end)

---------------------------------------------------------------- a group
add({ tap(" GROUPS 0 ", 2), tap(" + NEW ", FOOT), tapField("Name", 9, DET) })
add(typed("Nuclear", 7))
add({ tap(" ADD EVERY SWITCH ", DET) })
seen(function() found.joined = M.find("11 switches joined Nuclear.", DET) and M.find("11: MOX 1, MOX 2", DET) end)
add({ tapField("off above", 10, DET + 3) })
add(typed("95", 3))
add({ tapField("below", 6, DET + 3) })
add(typed("90", 3))
add({ tapField("% run", 6, DET + 3) })
add(typed("4", 3))
add({ tap(" + STEP ", DET) })
add({ tapField("off above", 10, DET + 4) })
add(typed("85", 3))
add({ tapField("below", 6, DET + 4) })
add(typed("75", 3))
add({ tapField("% run", 6, DET + 4) })
add(typed("6", 3))
seen(function()
  found.group = M.find("4 below 90% (off above 95%), 10 below 75% (back above 85%); least run time first", 4)
    and M.find("= 10 on", DET)
  H.screen("lumen-setup-groups")
end)

---------------------------------------------------------------- PAIR
add({ tap(" SWITCHES 12 ", 2), tap(" PAIR ", FOOT) })
seen(function() found.explained = M.find("Which reactor does each switch run?", 3) and M.find("12 redstone switches, 12 reactors found.", 3) end)
add({ tap(" START ", FOOT) })
seen(function() found.allOff = (rs[3].out[1] or 0) == 0 end)
waitFor(function() return M.find(" APPLY ", FOOT) end, "PAIR to finish")
seen(function()
  found.pairs = {
    one = M.find("✓ Reactor e001", 4), crossed = M.find("✓ Reactor e005", 4) and M.find("✓ Reactor e002", 4),
    fault = M.find("skipped: its fault input says trouble", 4),
    none = M.find("nothing started in 15 s", 4),
    apply = M.find(" APPLY 9 PAIRS ", FOOT),
    restored = (rs[3].out[1] or 0) == 15 and (rs[1].out[1] or 0) == 0 and (rs[2].out[1] or 0) == 0,
  }
  H.screen("lumen-setup-pair")
end)
add({ tap(" APPLY 9 PAIRS ", FOOT) })
seen(function() found.applied = M.find("9 sources set", FOOT - 1) and M.find("Reactor e005", 4) end)

-- STOP part-way: everything back at once.
add({ tap(" PAIR ", FOOT), tap(" START ", FOOT) })
waitFor(function() return M.find("▶ on now", 4) end, "a switch on test")
add({ tap(" STOP ", FOOT) })
seen(function()
  local on = 0
  for k = 1, 12 do if (rs[k].out[1] or 0) > 0 then on = on + 1 end end
  found.stopped = on == 1 and (rs[3].out[1] or 0) == 15 and M.find("stopped", 4) and M.find(" BACK ", FOOT)
end)
add({ tap(" BACK ", FOOT) })

---------------------------------------------------------------- big mode
add({ tap(" GENERAL ", 2) })
seen(function() found.bigRow = M.find("Big mode", 4) and M.find("after 5   min idle", 4) and M.find("radar: within 6 ", 4) end)
add({ tapField("after", 7, 4) })
add(typed("2", 3))
add({ tapField("blocks, only", 14, 4) })
add(typed("Steve, Alex"))
seen(function() found.wake = M.find("Steve, Alex", 4) end)
add({ tapField("Who switches", 18, 4) })
add(typed("Steve"))

---------------------------------------------------------------- save
add({ tap(" SAVE ", FOOT), tap(" SAVE ", FOOT), tap(" QUIT ", FOOT) })
local ok, err = setup()
check(ok, "lumen-setup's screen runs" .. (ok and "" or (": " .. tostring(err))))
check(found.up and found.down, "▲ and ▼ move a switch")
check(found.trip, "a heat trip: 90% (the default), or rising 5% a minute")
check(found.runsPick and found.always, "Runs ▸: by fill, always or a group; MOX 12 always on")
check(found.joined, "a group, named; ADD EVERY SWITCH adds the 11 that run by their own marks")
check(found.group, "two steps: 4 below 90%, 10 below 75%")
check(found.explained, "PAIR explains what it will do before START")
check(found.allOff, "START: every switch off first")
local p = found.pairs or {}
check(p.one and p.crossed, "each switch alone: its reactor, crossed wiring and all")
check(p.fault and p.none, "a fault input on: skipped; a block that runs nothing (or a reactor already running): said")
check(p.apply and p.restored, "9 pairs found; every output back as it was (block 3 on again)")
check(found.applied, "APPLY: the switches' sources")
check(found.stopped, "STOP part-way: every output back at once")
check(found.bigRow, "GENERAL: big mode after 5 min, and the radar found to wake it")
check(found.wake, "who wakes it: Steve and Alex")

local c = assert(config.load(CFG))
local sw = {}
for _, s in ipairs(c.control) do sw[s.name] = s end
check(c.control[1].name == "MOX 1" and c.control[2].name == "MOX 2", "the order as left")
check(sw["MOX 1"].heatTrip == 90 and sw["MOX 1"].heatRise == 5 and sw["MOX 2"].heatTrip == nil, "the heat trip, on MOX 1 only")
local g = c.groups[1]
check(g and g.name == "Nuclear" and #g.steps == 2 and g.steps[1].onBelow == 90 and g.steps[1].offAbove == 95 and g.steps[1].run == 4
  and g.steps[2].onBelow == 75 and g.steps[2].offAbove == 85 and g.steps[2].run == 6, "the group and its steps saved")
local members = 0
for _, s in ipairs(c.control) do if s.group == "Nuclear" then members = members + 1 end end
check(members == 11 and sw["MOX 12"].always == true and sw["MOX 12"].group == nil and sw["MOX 12"].onBelow == nil
  and sw["MOX 1"].onBelow == nil, "11 in the group, MOX 12 always on; none of them with marks")
check(c.operators and c.operators[1] == "Steve" and #c.operators == 1, "who can switch: Steve")
check(c.glanceAfter == 120 and c.wakePlayers and c.wakePlayers[1] == "Steve" and c.wakePlayers[2] == "Alex" and c.glanceScale == 3,
  "big mode saved: after 2 minutes, woken by Steve or Alex")
check(sw["MOX 1"].source == "Reactor e001" and sw["MOX 2"].source == "Reactor e005" and sw["MOX 5"].source == "Reactor e002"
  and sw["MOX 4"].source == nil and sw["MOX 6"].source == nil and sw["MOX 12"].source == nil, "the sources PAIR found, saved")

---------------------------------------------------------------- tier 2
M.resize(80, 25)
M.oob = 0
found = {}
steps = {}
add({ tap(" SWITCHES 12 ", 2), tap("MOX 1 ", 4) })
seen(function()
  found.switch = M.oob == 0 and M.find("Heat trip", 15) and M.find("Fault", 15) and M.find(" DELETE ", 15) and M.find(" ▲ ", 15)
    and M.find("Nuclear ▸", 15) and M.find(" PAIR ", 25)
end)
add({ tap(" GROUPS 1 ", 2), tap("Nuclear", 4) })
seen(function()
  found.group = M.oob == 0 and M.find("Step 2", 15) and M.find(" + STEP ", 15) and M.find(" ADD EVERY SWITCH ", 15)
  H.screen("lumen-setup-groups-tier2")
end)
add({ tap(" GENERAL ", 2) })
seen(function()
  found.general = M.oob == 0 and M.find("Wake it", 4) and M.find("Start on boot", 4)
  H.screen("lumen-setup-general-tier2")
end)
add({ tap(" QUIT ", 25) })
ok, err = setup()
check(ok and found.switch, "tier 2: a switch's panel fits, heat trip and fault and all" .. (ok and "" or (": " .. tostring(err))))
check(found.group, "tier 2: a group's panel fits")
check(found.general, "tier 2: GENERAL fits, big mode and all")
M.resize(160, 50)

H.done()
