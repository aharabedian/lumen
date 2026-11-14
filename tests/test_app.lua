-- test_app.lua: lumen with a vacuum reactor behind a redstone switch, through whole cycles: off above 90%, on
-- below 30%, no drain alerts while it's off by design (though the LSC's hour says empty in 2 hours), an alert
-- when it's on and can't keep up, the POWER rows and their AUTO / ON / OFF, a mode kept across a restart, the
-- LSC's own page, and what goes to LENS.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local Gen = require("gen")
local Net = require("net")
local check = H.check

local function writeCfg(name, body)
  local path = H.TMP .. "/" .. name .. ".cfg"
  local f = assert(io.open(path, "w"))
  f:write("return {\n" .. body .. "\n}\n")
  f:close()
  return path
end

-- The base: one LSC, a 100k EU/t load, a reactor making `gen` EU/t while the redstone signal is on.
local CAP = 1e10
local lsc = LSC.new{ stored = 9.5e9, capacity = CAP, inSec = 0, outSec = 100000, in1h = 40000, out1h = 100000 }
local rs = Gen.redstone()
local reactor = Gen.reactor{ heat = 0, maxHeat = 10000, output = 300000, produces = false }
local world = { gen = 300000, load = 100000 }
local function step(dt)
  local on = (rs.out[2] or 0) > 0
  reactor.state.produces = on
  local inEut = on and world.gen or 0
  local s = lsc.state
  s.stored = math.max(0, math.min(CAP, s.stored + (inEut - world.load) * 20 * dt))
  s.inSec, s.outSec, s.in5m, s.out5m = inEut, world.load, inEut, world.load
  s.timeTo = inEut < world.load and "empty" or "full"
  s.timeText = nil
end
M.components = { ["d2440f27-52c9"] = lsc.entry, ["5e1f0000-0000"] = rs.entry, ["eeee0000-0000"] = reactor.entry }

local function run(cfgPath, untilTime, onPull)
  M.pulls = 0
  local quitAt, last = nil, M.time
  M.onPull = function(n)
    step(M.time - last)
    last = M.time
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
  check(ok and #errs == 0, "runs without errors" .. ((ok and #errs == 0) and "" or (": " .. tostring(err or errs[1]))))
end

local function tapText(text, minY, minX)
  local x, y = M.find(text, minY, minX)
  assert(x, "nothing to tap: " .. text)
  return { "touch", "scr", x + 1, y, 0, "p" }
end

local net = Net.new()
local hub = net:endpoint("hub")
hub.open(4243)
M.modem = net:endpoint("lumen")
local cfgPath = writeCfg("vac", [[
  names = { d2440f27 = "Main" },
  sources = { { address = "eeee", name = "Vac reactor" } },
  control = { { name = "Vac nuke", redstone = "5e1f", side = "north", onBelow = 30, offAbove = 90, source = "Vac reactor" } },
  lensPort = 4243, lensNode = "power-room",
]])

---------------------------------------------------------------- a whole cycle
M.resize(160, 50)
M.setTime(0)
local seen = { driftAlert = false, beeps = 0 }
run(cfgPath, 6000, function(_, t)
  if M.find("(1 h average)", 1) or M.find("draining with", 1) then seen.driftAlert = true end
  if t > 1500 and t < 1600 and not seen.standby then
    seen.standby = {
      row = M.find("Vac nuke", 30) and M.find("OFF", 30) and M.find("auto: on below 30%, off above 90%", 30),
      eta = M.find("standby, empty in", 3),
      signal = rs.out[2] or 0,
    }
  end
  if not seen.onAt and (rs.out[2] or 0) > 0 then seen.onAt, seen.fillOn = t, lsc.state.stored / CAP end
  if seen.onAt and not seen.running and t > seen.onAt + 30 then
    seen.running = M.find("running", 30) and M.find("300.00k EU/t", 30) and M.find("ON    auto:", 30)
  end
  if seen.onAt and not seen.offAt and (rs.out[2] or 0) == 0 then seen.offAt, seen.fillOff = t, lsc.state.stored / CAP end
end)
H.screen("lumen-control")
check(seen.standby and seen.standby.row and seen.standby.signal == 0, "off above 90%, waiting between the marks")
check(seen.standby.eta, "the panel says it's standby while it drains")
check(seen.onAt and seen.fillOn < 0.305 and seen.fillOn > 0.28, ("switched on at 30%% (%.1f%%)"):format((seen.fillOn or 0) * 100))
check(seen.running, "POWER: the reactor running at 300k EU/t, the switch on")
check(seen.offAt and seen.fillOff > 0.895, ("switched off again at 90%% (%.1f%%)"):format((seen.fillOff or 0) * 100))
check(not seen.driftAlert, "no drain alert all cycle, though the LSC's hour says empty in under 2 hours")
check(M.beeps == 0, "and no beeps")

---------------------------------------------------------------- on, and it can't keep up
world.gen = 60000
lsc.state.stored = 2.5e9
local t0 = M.time
seen.alert = nil
run(cfgPath, t0 + 1300, function(_, t)
  if not seen.alert and M.find("Main empty in", 1) then seen.alert = { t = t - t0, text = M.find("(draining with Vac nuke on)", 1) } end
end)
check(seen.alert and seen.alert.text, "on and still draining: 'empty in ... (draining with Vac nuke on)'")
check(seen.alert.t >= 900, ("not before 10 minutes on and 5 minutes held (%.1fs)"):format(seen.alert and seen.alert.t or -1))
world.gen = 300000

---------------------------------------------------------------- by hand, kept across a restart
local _, swY = M.find("Vac nuke", 30)
run(cfgPath, M.time + 30, function(n)
  if n == 2 then return tapText(" OFF ", swY, 120) end
end)
check((rs.out[2] or 0) == 0 and M.find("by hand: set OFF on the screen", swY), "OFF: the signal goes at once")
run(cfgPath, M.time + 30)
check((rs.out[2] or 0) == 0 and M.find("by hand", swY), "a restart keeps OFF")
run(cfgPath, M.time + 30, function(n)
  if n == 2 then return tapText(" AUTO ", swY, 120) end
end)
check(M.find("auto:", swY), "AUTO: back to following the fill")

---------------------------------------------------------------- the LSC's page
run(cfgPath, M.time + 60, function(n)
  if n == 2 then return tapText("Main", 3) end
  if n == 4 then return tapText(" 8 H ", 3) end
end)
H.screen("lumen-detail")
check(M.find("◀ BACK", 3) and M.find("LAST 24 H", 3) and M.find("24 H BEFORE", 3), "tap an LSC: its page")
check(M.find("Vac nuke on for", 3), "how long the switch was on")
local x8 = M.find(" 8 H ", 3)
local _, y8 = M.find(" 8 H ", 3)
check(M.bgAt(x8, y8) == 0x2f6fb5, "8 H chosen")
check(M.find("In ", 3) and M.find("Out ", 3) and M.find("Net ", 3) and M.find("5 min", 3), "the averages table")
check(M.find("capacitors: UHV 0 · UEV 0 · UIV 0", 3), "capacitors, in tier order")

---------------------------------------------------------------- tier 2
M.resize(80, 25)
M.oob = 0
run(cfgPath, M.time + 20)
H.screen("lumen-control-tier2")
check(M.oob == 0 and M.find("POWER", 3) and M.find(" AUTO ", 3), "tier 2: POWER fits, with its buttons")
run(cfgPath, M.time + 20, function(n) if n == 2 then return tapText("Main", 3) end end)
H.screen("lumen-detail-tier2")
check(M.oob == 0 and M.find("◀ BACK", 3) and M.find("LAST 24 H", 3), "tier 2: the LSC's page fits")
M.resize(160, 50)

---------------------------------------------------------------- LENS
local last
while true do
  local ev = net.pop(hub)
  if not ev then break end
  local msg = require("lumen.lens.codec").decode(ev[6])
  if msg and msg.kind == "snapshot" then last = msg end
end
local function sample(name, key, value)
  for _, x in ipairs(last.samples) do if x[1] == name and x[3] and x[3][key] == value then return x[2] end end
end
check(sample("lumen_switch_on", "switch", "Vac nuke") ~= nil and sample("lumen_switch_auto", "switch", "Vac nuke") == 1,
  "LENS: the switch, and that it's on auto")
check(sample("lumen_source_up", "source", "Vac reactor") == 1 and sample("lumen_reactor_heat_ratio", "source", "Vac reactor") == 0,
  "LENS: the reactor and its heat")
check((sample("lumen_in_24h_eu", "lsc", "Main") or 0) > 0 and (sample("lumen_out_24h_eu", "lsc", "Main") or 0) > 0,
  "LENS: the last 24 hours' EU in and out")
M.modem = nil

H.done()
