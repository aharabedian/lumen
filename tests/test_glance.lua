-- test_glance.lua: big mode on a 7 x 3 wall. Big after glanceAfter seconds without a tap or anyone near (big
-- digits, the time to full, how many run, the groups, the worst alert); waking: a tap anywhere (which presses
-- nothing underneath), or a player walking up to a Computronics radar; someone standing near keeps it awake;
-- BIG by hand; wakeRange, wakePlayers; no radar; glanceAfter = 0.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local Gen = require("gen")
local check = H.check
local C = require("lumen.frame").C

local CAP = 2.214e10
local lsc = LSC.new{ stored = 0.72 * CAP, capacity = CAP, inSec = 44000, outSec = 77000, in1h = 40000, out1h = 40000 }
local rs, reactors = {}, {}
local base = { ["d2440f27-52c9"] = lsc.entry }
for k = 1, 5 do
  rs[k] = Gen.redstone()
  reactors[k] = Gen.reactor{ heat = 1000, maxHeat = 10000, output = 43600, produces = false }
  base[("c%03d0000-0000"):format(k)] = rs[k].entry
  base[("e%03d0000-0000"):format(k)] = reactors[k].entry
end
local radar = Gen.radar()
local function room(extra)
  M.components = {}
  for a, e in pairs(base) do M.components[a] = e end
  for a, e in pairs(extra or {}) do M.components[a] = e end
end

local cfgPath = H.TMP .. "/lumen.cfg"
local function writeCfg(extra)
  local f = assert(io.open(cfgPath, "w"))
  f:write(([[return {
  heatWarn = 95, heatBad = 98, glanceAfter = 60, wakeRange = 6, %s
  sources = { { address = "e001", name = "N-1" }, { address = "e002", name = "N-2" }, { address = "e003", name = "N-3" },
    { address = "e004", name = "N-4" }, { address = "e005", name = "S-6" } },
  groups = { { name = "Quad Uranium", steps = { { onBelow = 75, offAbove = 90, run = 1 }, { onBelow = 50, offAbove = 65, run = 3 } } } },
  control = {
    { name = "Reactor N-1", redstone = "c001", side = "top", group = "Quad Uranium", source = "N-1", heatTrip = 50 },
    { name = "Reactor N-2", redstone = "c002", side = "top", group = "Quad Uranium", source = "N-2", heatTrip = 50 },
    { name = "Reactor N-3", redstone = "c003", side = "top", group = "Quad Uranium", source = "N-3", heatTrip = 50 },
    { name = "Reactor N-4", redstone = "c004", side = "top", group = "Quad Uranium", source = "N-4", heatTrip = 50 },
    { name = "Reactor S-6", redstone = "c005", side = "top", always = true, source = "S-6", heatTrip = 75 },
  },
}
]]):format(extra or ""))
  f:close()
end

local function step()
  for k = 1, 5 do reactors[k].state.produces = (rs[k].out[1] or 0) > 0 end
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
local function isBig() return M.resolution and M.resolution[1] == 53 end
local function tapAt(text, minY, minX)
  local x, y = M.find(text, minY, minX)
  assert(x, "nothing to tap: " .. text)
  return { "touch", "scr", x + 1, y, 0, "p" }
end

M.resize(160, 50)
M.aspect = { 7, 3 }

---------------------------------------------------------------- a radar: big, then a player walks up
room({ ["r0010000-0000"] = radar.entry })
writeCfg()
M.setTime(0)
local t0 = 0
local seen = {}
run(t0 + 220, function(_, t)
  if not seen.bigAt and isBig() then
    seen.bigAt = t - t0
    seen.big = {
      size = M.resolution[2] == 11,
      text = M.find("tap to wake", 1) and M.find("of 5 running", 1) and M.find("Quad Uranium 1 of 4 on", 1)
        and M.find("net -33.00k EU/t", 1),
      digits = M.bgAt(3, 3) == C.good and M.bgAt(19, 3) == C.good,   -- "72%": the 7's top, the %'s corner
      alert = M.find("All good.", 11),
      calls = radar.calls,
    }
    H.screen("lumen-big")
  end
  if t >= t0 + 100 and not seen.arrived then
    radar.players = { { name = "Steve", distance = 4 } }
    seen.arrived = t
  end
  if seen.arrived and not seen.wokeAt and not isBig() then seen.wokeAt, seen.callsAwake = t - seen.arrived, radar.calls end
  if t >= t0 + 210 and not seen.stayed then
    seen.stayed = not isBig() and M.find("POWER", 3) and radar.calls - seen.callsAwake
  end
end)
check(seen.bigAt and seen.bigAt >= 60 and seen.bigAt <= 70, ("big a minute after the last tap (%s s)"):format(tostring(seen.bigAt)))
check(seen.big.size, "big mode: 53 x 11 on the wall (a third of 160 x 33)")
check(seen.big.digits, "72% in big digits")
check(seen.big.text, "what to know from across the room: how many run, the group, the net")
check(seen.big.alert, "and the worst alert (none)")
check(seen.big.calls == 1, "the radar asked once while awake: just before going big")
check(seen.wokeAt and seen.wokeAt <= 3, ("a player walks up: awake in %s s, no tap"):format(tostring(seen.wokeAt)))
check(seen.stayed and seen.stayed <= 2, "they stay near for 2 minutes: it stays awake, asking the radar once a minute")

---------------------------------------------------------------- they leave; too far; a tap wakes it
radar.players = {}
seen = {}
t0 = M.time
run(t0 + 160, function(_, t)
  if not seen.bigAt and isBig() then seen.bigAt = t - t0; radar.players = { { name = "Steve", distance = 7 } } end
  if seen.bigAt and t > t0 + 100 and not seen.far then seen.far = isBig() end
  if seen.far and not seen.tapped then
    seen.tapped = true
    return { "touch", "scr", 40, 8, 0, "p" }
  end
  if seen.tapped and not seen.awake then seen.awake = not isBig() and M.find(" AUTO ", 3) and not M.find("by hand", 3) end
end)
check(seen.bigAt and seen.bigAt <= 70, "they leave: big again a minute later")
check(seen.far, "a player 7 blocks away (wakeRange 6) doesn't wake it")
check(seen.awake, "a tap anywhere wakes it, and presses nothing underneath")

---------------------------------------------------------------- BIG by hand, with someone standing there
radar.players = { { name = "Steve", distance = 3 } }
seen = {}
t0 = M.time
run(t0 + 60, function(n, t)
  if n == 2 then return tapAt(" BIG ", 1) end
  if t > t0 + 15 and t < t0 + 25 then seen.stays = isBig() end
  if t >= t0 + 25 and not seen.left then seen.left = t; radar.players = {} end
  if seen.left and t >= seen.left + 10 and not seen.back then seen.back = t; radar.players = { { name = "Steve", distance = 3 } } end
  if seen.back and not seen.woke and not isBig() then seen.woke = t - seen.back end
end)
check(seen.stays, "BIG by hand: big at once, and the player who tapped it doesn't wake it")
check(seen.woke and seen.woke <= 3, "they leave and come back: awake")

---------------------------------------------------------------- wakePlayers
writeCfg('wakePlayers = { "Alex" },')
radar.players = {}
seen = {}
t0 = M.time
run(t0 + 130, function(_, t)
  if isBig() and not seen.big then seen.big = t; radar.players = { { name = "Steve", distance = 2 } } end
  if seen.big and t > seen.big + 20 and not seen.steve then seen.steve = isBig(); radar.players = { { name = "Alex", distance = 5 } } end
  if seen.steve and not isBig() and not seen.alex then seen.alex = true end
end)
check(seen.steve and seen.alex, "wakePlayers = { \"Alex\" }: Steve doesn't wake it, Alex does")

---------------------------------------------------------------- no radar: only a tap wakes it
writeCfg()
room()
seen = {}
t0 = M.time
local radarCalls = radar.calls
run(t0 + 100, function(_, t)
  if isBig() and not seen.big then seen.big = t - t0; seen.tapAt = t + 10 end
  if seen.tapAt and t >= seen.tapAt and not seen.tapped then seen.tapped = true; return { "touch", "scr", 20, 6, 0, "p" } end
  if seen.tapped and seen.woke == nil then seen.woke = not isBig() end
end)
check(seen.big and seen.big <= 70 and seen.woke, "no radar: big after a minute, and a tap wakes it")
check(radar.calls == radarCalls, "nothing polled")

---------------------------------------------------------------- glanceAfter = 0
writeCfg("glanceAfter = 0,")
room()
seen = {}
t0 = M.time
run(t0 + 200, function(n, t)
  if t > t0 + 150 and seen.full == nil then seen.full = not isBig() end
  if seen.full and not seen.tapped then seen.tapped = true; return tapAt(" BIG ", 1) end
  if seen.tapped and seen.big == nil then seen.big = isBig() end
  if n and seen.big and not seen.woken then seen.woken = true; return { "touch", "scr", 5, 5, 0, "p" } end
end)
check(seen.full, "glanceAfter = 0: no big mode by itself")
check(seen.big, "BIG still works")
M.aspect = nil
M.resize(160, 50)

H.done()
