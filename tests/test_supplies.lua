-- test_supplies.lua: supplies counted in an AE2 ME system (lumen.supplies: one lookup each through an adapter on
-- an ME interface; lumen-setup's search), their history and rate (lumen.history), what's wrong with them
-- (supplies.status and the alerts), then lumen: the SUPPLIES section, its page, big mode and LENS; and lumen-setup:
-- finding one by the name its tooltip shows, its alerts, what it feeds, saved.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local Gen = require("gen")
local check = H.check
local component = require("component")
local config = require("lumen.config")
local supplies = require("lumen.supplies")
local history = require("lumen.history")
local alerts = require("lumen.alerts")

local function bad(t, text)
  local c, err = config.check(t)
  return c == nil and err and err:find(text, 1, true) ~= nil
end

---------------------------------------------------------------- settings
check(config.check({ supplies = { { name = "Rods", item = "gregtech:gt.reactorUraniumQuad", below = 64, hours = 24 },
  { name = "Coolant", fluid = "ic2coolant" } } }), "an item and a fluid")
check(bad({ supplies = { { name = "X" } } }, "needs item"), "a supply needs an item or a fluid")
check(bad({ supplies = { { name = "X", item = "a", fluid = "b" } } }, "one of them"), "not both")
check(bad({ supplies = { { name = "X", item = "a", below = -1 } } }, "below must be"), "below is 0 or more")
check(bad({ supplies = { { name = "X", item = "a" }, { name = "X", fluid = "b" } } }, "two supplies have that name"), "names are unique")

---------------------------------------------------------------- reading and searching
local ROD = "gregtech:gt.reactorUraniumQuad"
local me = Gen.me({ { name = ROD, damage = 0, label = "Quad Fuel Rod (Uranium)", size = 312 },
  { name = ROD, damage = 1, label = "Something else", size = 5 },
  { name = "IC2:reactorUraniumQuaddepleted", damage = 0, label = "Quad Fuel Rod (Depleted Uranium)", size = 1880 } },
  { { name = "ic2coolant", label = "IC2 Coolant", amount = 2100000 } })
M.components = { ["ae000000-0000"] = me.entry }
local cfg = config.check({ supplies = {
  { name = "Quad rods", item = ROD, below = 64, hours = 24, feeds = "Quad Uranium" },
  { name = "Spent rods", item = "IC2:reactorUraniumQuaddepleted", above = 2000 },
  { name = "Coolant", fluid = "ic2coolant", below = 100000 },
  { name = "Gone", item = "nope:nothing" } } })
local rs = supplies.new(component, cfg):read()
check(rs[1].ok and rs[1].amount == 312 and rs[1].kind == "item" and rs[1].label == "Quad Fuel Rod (Uranium)",
  "an item: its count (damage 0, not damage 1's)")
check(rs[3].ok and rs[3].amount == 2100000 and rs[3].kind == "fluid", "a fluid: its L")
check(rs[4].ok and rs[4].amount == 0, "none in the ME system: 0, not an error")
check(me.calls == 4, "one lookup each")
-- Search: every word typed in its name (or its registry name), any order, any case; best first.
check(supplies.score("quad uran", "Quad Fuel Rod (Uranium)", ROD) > supplies.score("quad uran", "Quad Fuel Rod (Depleted Uranium)", ROD),
  "a match: the closer name ranks higher")
check(supplies.score("quad uran", "Uranium 235", "x") == nil, "a word missing: no match")
check(supplies.score("reactoruranium", "Quad Fuel Rod (Uranium)", ROD), "the registry name counts too")
check(supplies.score("quad fuel rod (uranium)", "Quad Fuel Rod (Uranium)", ROD) > supplies.score("quad uran", "Quad Fuel Rod (Uranium)", ROD),
  "the whole name, best of all")
local function searchAll(text)
  local s = assert(supplies.search(component, text))
  local steps = 0
  while s:step(100) do steps = steps + 1 end
  return s, steps
end
local s1 = searchAll("quad uran")
check(#s1.results == 3 and s1.results[1].label == "Quad Fuel Rod (Uranium)" and s1.results[1].name == ROD and s1.results[1].damage == 0
  and s1.results[1].amount == 312 and s1.results[2].label == "Quad Fuel Rod (Depleted Uranium)",
  "part of a name: both rods, the closer first")
check(s1.results[3].label == "Something else", "a match on the registry name only, last")
local s2 = searchAll("cool")
check(#s2.results == 1 and s2.results[1].kind == "fluid" and s2.results[1].name == "ic2coolant", "a fluid by part of its name")

-- A big ME system: looked through a step at a time, never all at once; STOP keeps what's found.
local many = {}
for k = 1, 3000 do many[k] = { name = "mod:junk", damage = k, label = "Junk " .. k, size = k } end
many[2500] = { name = ROD, damage = 0, label = "Quad Fuel Rod (Uranium)", size = 312 }
local bigMe = Gen.me(many, {})
M.components = { ["ae000000-0000"] = bigMe.entry }
local s3, stepCount = searchAll("quad uran")
check(stepCount >= 29 and s3.looked == 3000 and #s3.results == 1 and s3.done, ("3000 items, 100 a step (%d steps)"):format(stepCount))
local s4 = assert(supplies.search(component, "junk 1"))
s4:step(100)
s4:stop()
check(s4.done and s4.looked == 100 and #s4.results > 0 and not s4:step(100), "STOP: done, what was found kept")
local s5 = assert(supplies.search(component, "junk"))
while s5:step(500) do end
check(#s5.results == supplies.MAX_RESULTS, "at most " .. supplies.MAX_RESULTS .. " results kept (the best)")
M.components = { ["ae000000-0000"] = me.entry }
me.broken = "unloaded"
check(supplies.new(component, cfg):read()[1].err == "unloaded", "an ME system that fails: why")
me.broken = nil
M.components = {}
local none, why = supplies.search(component, "x")
check(not none and why:find("no ME interface", 1, true) and supplies.new(component, cfg):read()[1].err:find("no ME", 1, true),
  "no ME interface or controller: said")

---------------------------------------------------------------- history and rate
local h = history.new()
local T = 1.8e9
for t = T, T + 2 * 3600, 30 do h:supply("Quad rods", 312 - 4 * (t - T) / 3600, t) end
local now = T + 2 * 3600
local rate = h:supplyRate("Quad rods", now, 3600)
check(rate and math.abs(rate + 4) < 0.3, ("the change per hour over the last hour (%s)"):format(tostring(rate)))
check(h:supplyRate("Quad rods", T + 1200, 3600) == nil, "not before there's half an hour of it")
local h2 = history.new(require("serialization").unserialize(require("serialization").serialize(h:save())))
check(math.abs(h2:supplyRate("Quad rods", now, 3600) - rate) < 1e-9, "kept across a restart")

---------------------------------------------------------------- status and alerts
local function r(amount, c, lasts, rt) return { name = "S", ok = true, amount = amount, cfg = c, lasts = lasts, rate = rt, kind = "item" } end
local function st(x) local level, text = supplies.status(x); return tostring(level) .. " " .. text end
check(st(r(0, { below = 64 })) == "bad none left", "none left")
check(st(r(40, { below = 64 })) == "warn low", "low")
check(st(r(2100, { above = 2000 })) == "warn piling up", "piling up")
check(st(r(300, { hours = 24 }, 20 * 3600)) == "warn lasts 20h 00m", "lasting under its hours")
check(st(r(300, { hours = 24 }, 3 * 86400)) == "nil lasts 3d 0h", "lasting long enough: how long")
check(st(r(300, {}, nil, 4)) == "nil +4/h", "growing")
check(st(r(300, {}, nil, 0)) == "nil steady", "steady")
check(st({ name = "S", ok = false, err = "x" }) == "warn can't be counted", "can't be counted")
local list = alerts.evaluate({ { name = "Main", address = "d", ok = true, fill = 0.5 } }, config.check({}), { now = 0,
  supplies = { r(40, { below = 64 }), { name = "T", ok = true, amount = 2100, cfg = { above = 2000 }, kind = "fluid" } } })
local texts = {}
for _, a in ipairs(list) do if a.id:find("^supply:") then texts[#texts + 1] = a.level .. " " .. a.text end end
table.sort(texts)
check(table.concat(texts, " | ") == "warn S low: 40 (under 64) | warn T piling up: 2.10k L (over 2.00k)", "alerts say what and how much")

---------------------------------------------------------------- lumen
local CAP = 2e10
local lsc = LSC.new{ stored = 0.6 * CAP, capacity = CAP, inSec = 60000, outSec = 60000, in1h = 60000, out1h = 60000 }
me = Gen.me({ { name = ROD, damage = 0, label = "Quad Fuel Rod (Uranium)", size = 312 },
  { name = "IC2:reactorUraniumQuaddepleted", damage = 0, label = "Quad Fuel Rod (Depleted Uranium)", size = 1995 } },
  { { name = "ic2coolant", label = "IC2 Coolant", amount = 2100000 } })
M.components = { ["d2440f27-52c9"] = lsc.entry, ["ae000000-0000"] = me.entry }
local cfgPath = H.TMP .. "/lumen.cfg"
local fh = assert(io.open(cfgPath, "w"))
fh:write(([[return {
  glanceAfter = 0,
  supplies = {
    { name = "Quad rods", item = %q, below = 64, hours = 100, feeds = "Quad Uranium" },
    { name = "Spent rods", item = "IC2:reactorUraniumQuaddepleted", above = 2000 },
    { name = "Coolant", fluid = "ic2coolant", below = 100000 },
  },
}
]]):format(ROD))
fh:close()
local function run(untilTime, onPull)
  M.pulls = 0
  local quitAt
  M.onPull = function(n)
    me.items[1].size = math.floor(312 - 4 * M.time / 3600)          -- burning 4 an hour
    me.items[2].size = math.floor(1995 + 4 * M.time / 3600)         -- and the spent ones piling up
    local e = onPull and onPull(n, M.time)
    if e then return e end
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
local function tapAt(text, minY)
  local x, y = M.find(text, minY)
  assert(x, "nothing to tap: " .. text)
  return { "touch", "scr", x + 1, y, 0, "p" }
end

M.resize(160, 50)
M.aspect = { 7, 3 }
M.setTime(0)
local calls0 = me.calls
run(2 * 3600)
check(me.calls - calls0 <= 2 * 3600 / 30 * 3 + 6, ("counted every 30 s, not every reading (%d lookups)"):format(me.calls - calls0))
local seen = {}
local t1 = M.time
run(M.time + 120, function(n, t)
  if t >= t1 + 75 and not seen.section then              -- alerts wait a minute
    seen.section = M.find("SUPPLIES", 3) and M.find("Quad rods", 3) and M.find("Spent rods", 3) and M.find("Coolant", 3)
      and M.find("2.10M L", 3) and M.find("lasts", 3)
    seen.alerts = M.find("Quad rods lasts", 3) and M.find("(under 100 h)", 3) and M.find("Spent rods piling up", 3)
    H.screen("lumen-supplies-main")
    seen.tapAt = n
    return tapAt("SUPPLIES", 3)
  end
  if seen.tapAt and n == seen.tapAt + 2 then
    seen.page = M.find("◀ BACK", 3) and M.find("PER HOUR", 3) and M.find("LAST 24 H", 3) and M.find("Quad Uranium", 3)
      and M.find(" -4 ", 5) and M.find("under 64, < 100 h left", 5) and M.find("over 2.00k", 5)
    seen.oob = M.oob
    H.screen("lumen-supplies")
  end
end)
check(seen.section, "SUPPLIES on the main page: each one's stock and how long it lasts")
check(seen.alerts, "alerts: lasting under its hours, spent rods piling up")
check(seen.page, "the page: per hour, the last 24 hours, the alerts set, what it feeds")
check(seen.oob == 0, "fits the 7 x 3 wall")

M.aspect = nil
M.resize(80, 25)
M.oob = 0
seen = {}
run(M.time + 20, function(n)
  if n == 2 then return tapAt("SUPPLIES", 3) end
  if n == 4 then seen.fits = M.oob == 0 and M.find("PER HOUR", 3) and M.find("Coolant", 5) end
end)
check(seen.fits, "tier 2: the page fits")
M.resize(160, 50)

---------------------------------------------------------------- lumen-setup
local prefix = H.TMP .. "/root"
local home = prefix .. "/home"
os.execute('mkdir -p "' .. home .. '"')
local realGetenv = os.getenv
os.getenv = function(k) if k == "LUMEN_PREFIX" then return prefix end return realGetenv(k) end -- luacheck: ignore 122
local CFG = home .. "/lumen.cfg"
fh = assert(io.open(CFG, "w"))
fh:write('return { groups = { { name = "Quad Uranium", steps = { { onBelow = 75, offAbove = 90, run = 1 } } } } }\n')
fh:close()
local steps = {}
local function at(x, y) return { "touch", "scr", x, y, 0, "p" } end
local function tap(text, minY)
  return function()
    local x, y = M.find(text, minY)
    if not x then
      local rows = {}
      for ry = 1, M.H do rows[#rows + 1] = M.row(ry) end
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
  for ch in text:gmatch(".") do out[#out + 1] = key(ch:byte(), 0) end
  out[#out + 1] = key(13, 28)
  return out
end
local function add(l) for _, s in ipairs(l) do steps[#steps + 1] = s end end
local function seenStep(fn) steps[#steps + 1] = function() fn(); return nil end end
local function waitFor(fn, label)
  local tries = 0
  local w
  w = function()
    tries = tries + 1
    if fn() then return nil end
    assert(tries < 200, "waited too long for " .. label)
    table.insert(steps, 1, w)
    return nil
  end
  steps[#steps + 1] = w
end

local DET, FOOT = 40, 50
seen = {}
for k = 1, 3000 do table.insert(me.items, 1, { name = "mod:junk", damage = k, label = "Junk " .. k, size = k }) end
add({ tap(" SUPPLIES 0 ", 2), tap(" + NEW ", FOOT) })
seenStep(function() seen.find = M.find("Add a supply: what's it called?", 1) and M.find("FIND", 6) end)
add(typed("zzz"))
waitFor(function()
  if M.find("Looking... ", 7) and M.find(" STOP ", 6) then seen.progress = true end
  return M.find("Looked through", 7)
end, "the search")
seenStep(function() seen.nothing = M.find('nothing has every word of "zzz"', 7) end)
add({ tapField("Name", 7, 6) })
add(typed("quad uran", 3))
waitFor(function() return M.find("Looked through 3002 items", 7) end, "the search")
seenStep(function()
  local _, y1 = M.find("Quad Fuel Rod (Uranium)", 9)
  local _, y2 = M.find("Quad Fuel Rod (Depleted Uranium)", 9)
  seen.results = M.find("Tap the one to watch", 8) and M.find(ROD .. ":0", 9) and y1 and y2 and y1 < y2
  H.screen("lumen-setup-find")
end)
add({ tap("Quad Fuel Rod (Uranium)", 9) })
seenStep(function() seen.added = M.find("Added Quad Fuel Rod (Uranium)", FOOT - 1) and M.find(" SUPPLIES 1 ", 2) end)
add({ tapField("under", 7, DET + 3) })
add(typed("64"))
add({ tapField("or under", 10, DET + 3) })
add(typed("48"))
add({ tap("nothing said ▸", DET + 4), tap("Quad Uranium", 3) })
add({ tap(" COUNT ", DET) })
seenStep(function() seen.count = M.find("in the ME system now", FOOT - 1); H.screen("lumen-setup-supplies") end)
add({ tap(" SAVE ", FOOT), tap(" SAVE ", FOOT), tap(" QUIT ", FOOT) })
M.pulls = 0
M.onPull = function()
  local s = table.remove(steps, 1)
  if s then return s() end
  return { "interrupted" }
end
local realPrint = print
print = function() end -- luacheck: ignore 121
local ok, err = pcall(H.run, "lumen-setup.lua")
print = realPrint -- luacheck: ignore 121
M.onPull = nil
check(ok, "lumen-setup runs" .. (ok and "" or (": " .. tostring(err))))
check(seen.find and seen.nothing, "+ NEW asks for part of its name; nothing matching says so")
check(seen.progress, "3000 items: looked through a step at a time, how far it's got and STOP on screen")
check(seen.results and seen.added, "\"quad uran\": both rods, the closer first; tap it to add it")
check(seen.count, "COUNT: how many the ME system has now")
local c = assert(config.load(CFG))
local sp = c.supplies[1]
check(sp and sp.name == "Quad Fuel Rod (Uranium)" and sp.item == ROD and sp.damage == 0 and sp.below == 64 and sp.hours == 48
  and sp.feeds == "Quad Uranium", "saved: what it counts, its alerts, what it feeds")

H.done()
