-- test_lumen.lua: the lumen program on the mock screen: one LSC on a big screen, several in two columns,
-- a tier 2 screen, alerts and their beep, QUIT, redrawing only what changed, and reporting to LENS (off by
-- default; describe, snapshots, hello answered, and the vendored LENS modules match ../lens).
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local Net = require("net")
local check = H.check

local function writeCfg(name, body)
  local path = H.TMP .. "/" .. name .. ".cfg"
  local f = assert(io.open(path, "w"))
  f:write("return {\n" .. body .. "\n}\n")
  f:close()
  return path
end

-- Run src/lumen.lua: `events(n, time)` gives the nth pulled event (or nil to let time pass). QUIT is tapped
-- once `untilTime` has passed.
local function run(cfgPath, untilTime, events)
  M.setTime(0)
  M.pulls = 0
  local quitAt
  M.onPull = function(n)
    local ev = events and events(n, M.time)
    if ev then return ev end
    if M.time >= untilTime then
      if not quitAt then quitAt = n; return { "touch", "scr", M.W - 3, 1, 0, "p" } end
      return { "interrupted" } -- QUIT didn't work: stop anyway (and fail below)
    end
  end
  local errs, slept = {}, M.slept
  local realStderr = io.stderr
  io.stderr = { write = function(_, s) errs[#errs + 1] = s end } -- luacheck: ignore 122
  local ok, err = pcall(H.run, "lumen.lua", cfgPath)
  io.stderr = realStderr -- luacheck: ignore 122
  check(ok and #errs == 0, "runs without errors" .. ((ok and #errs == 0) and "" or (": " .. tostring(err or errs[1]))))
  check(M.slept - slept == require("lumen.splash").SECONDS, "the SPECTRA logo shows while lumen starts")
  return quitAt
end

local main = LSC.new{ stored = 10773450724, capacity = 11340000000, inSec = 65536, outSec = 64716,
  in5m = 66082, out5m = 65712, in1h = 42420, out1h = 42338, timeTo = "full", timeText = "10.42 hours" }

---------------------------------------------------------------- one LSC, tier 3
M.components = { ["d2440f27-52c9"] = main.entry, ["ebf00000-0000"] = LSC.machine("multimachine.blastfurnace") }
M.resize(160, 50)
local cfgPath = writeCfg("one", 'names = { d2440f27 = "Main" },')
local quitAt = run(cfgPath, 30)
check(M.pulls == quitAt, "QUIT stops the program")
check(M.find("LUMEN", 1) and M.find(" OK ", 1) and M.find("1 LSC   95.0% full   net +820 EU/t", 1), "header: health, fill, net")
local _, y = M.find("Main", 2)
check(y == 3 and M.find("10.77G / 11.34G EU  95.0%", 3), "the panel: name, stored / capacity, percent")
local C = require("lumen.gui").C
check(M.bgAt(2, 4) == C.good and M.bgAt(2, 9) == C.good and M.bgAt(158, 4) == C.line,
  "a big screen gets a tall fill bar, green, filled to 95%")
check(M.find("in 65.54k   out 64.72k   net +820 EU/t", 3) and M.find("full in 10h 25m", 3), "flows and time to full")
check(M.find("net 5 min +370   1 h +82 EU/t", 3) and M.find("loss 65 EU/t   maintenance ok", 3), "longer averages, loss, maintenance")
check(M.find("▄▄", 13) == 2 and select(2, M.find("▄▄", 13)) == 13 and M.row(42):sub(1, 7) == " ██" and M.row(43):find("^%s*$"),
  "the rows left show the fill history: a chart, 95% of its height")
check(M.find("ALERTS (0)", 3) and M.find("All good.", 3), "no alerts")
check(not M.find("All LSCs", 1), "no total with one LSC")
check(M.find("No /home/lumen.cfg", 1) == nil, "a config file was given: no defaults note")
check((main.calls.setWorkAllowed or 0) == 0, "never changes anything in the game")

-- Redraws send only what changed: steady readings cost few GPU calls.
local before
M.gpuCalls = 0
run(cfgPath, 60, function(n)
  if n == 2 then before = M.gpuCalls end
end)
local perTick = (M.gpuCalls - before) / 11
check(perTick < 15, ("steady readings redraw little (%.1f GPU calls per reading)"):format(perTick))

-- An evening's history: draining while the EBFs run, then filling again. The chart shows it.
run(cfgPath, 4800, function(_, t)
  local drain = t < 2400
  main.state.stored = math.floor(drain and 10773450724 - t * 2.2e6 or 10773450724 - 2400 * 2.2e6 + (t - 2400) * 1.8e6)
  main.state.inSec, main.state.outSec = drain and 40000 or 160000, drain and 150000 or 70000
  main.state.timeTo, main.state.timeText = drain and "empty" or "full", drain and "5.12 hours" or "1.28 hours"
end)
H.screen("lumen-one")
local cx, cy = M.find("▁", 12)
check(cx and cy > 12, "the chart dips and recovers")
main.state.stored, main.state.inSec, main.state.outSec = 10773450724, 65536, 64716
main.state.timeTo, main.state.timeText = "full", "10.42 hours"

---------------------------------------------------------------- several LSCs, alerts
local spare = LSC.new{ stored = 4e8, capacity = 4e9, inSec = 0, outSec = 2000, in1h = 0, out1h = 12000,
  timeTo = "empty", timeText = "30 minutes" }
local third = LSC.new{ stored = 3e9, capacity = 4e9, inSec = 5000, outSec = 1000, maintenance = "needs_work" }
M.components = { ["d2440f27-52c9"] = main.entry, ["0aaa1111-0000"] = spare.entry, ["77770000-0000"] = third.entry }
M.beeps = 0
cfgPath = writeCfg("three", 'names = { d2440f27 = "Main", ["0aaa"] = "Spare", ["7777"] = "Backup" },')
run(cfgPath, 20)
check(M.find("Backup needs maintenance (needs_work)", 1) and not M.find("Spare low", 1) and not M.find("Spare empty", 1),
  "alerts wait their hold: maintenance at once, low fill after 30 s, draining after 5 minutes")
run(cfgPath, 330)
H.screen("lumen-three")
check(M.find(" BAD ", 1) and M.find("3 LSCs", 1), "header: bad health, three LSCs")
local _, ty = M.find("All LSCs", 2)
check(ty == 3, "the total comes first")
local bx, by = M.find("Backup", 4)
local mx, my = M.find("Main", 4)
local sx, sy = M.find("Spare", 4)
check(bx == 2 and mx > 70 and by == my and sx == 2 and sy > by, "LSCs in two columns, by name")
check(M.bgAt(2, sy + 1) == 0xff5c5c, "a bad LSC's bar is red")
check(M.find("Spare empty in 27m (1 h average)", 1) and M.find("Spare nearly empty: 10.0%", 1) == nil and M.find("Spare low: 10.0%", 1),
  "alerts: draining soon (bad) and low (warn)")
check(M.find("Backup needs maintenance (needs_work)", 1), "alerts: maintenance")
local _, ay = M.find("Spare empty in 27m (1 h average)", 1)
local _, ly = M.find("Spare low", 1)
check(ay < ly and M.find(" BAD ", ay), "bad alerts first, tagged")
check(M.beeps == 1, "one beep for the new bad alert, not every reading")

---------------------------------------------------------------- tier 2, no config, an LSC that can't be read
M.resize(80, 25)
spare.state.broken = "chunk unloaded"
run(H.TMP .. "/missing.cfg", 10)
H.screen("lumen-tier2")
check(M.oob == 0, "nothing drawn off a tier 2 screen")
check(M.find("No /home/lumen.cfg: defaults", 1), "no config: says defaults apply")
check(M.find("can't be read: ", 1) and M.find("can't be read: chunk unloaded", 1), "an LSC that can't be read says why")
spare.state.broken = nil

M.components = {}
M.resize(160, 50)
run(H.TMP .. "/missing.cfg", 10)
check(M.find("No LSC found", 1) and M.find("WARN", 1), "no LSC: says what to do, and warns")

---------------------------------------------------------------- resolution
M.components = { ["d2440f27-52c9"] = main.entry }
cfgPath = writeCfg("big", "resolution = { 80, 25 },")
M.resize(160, 50)
run(cfgPath, 10)
check(M.find("QUIT", 1) == 72 + 3 and M.oob == 0, "resolution: drawn for 80 x 25")

---------------------------------------------------------------- LENS
local codec = require("lumen.lens.codec")
local net = Net.new()
local hub = net:endpoint("hub")
hub.open(4243)
M.modem = net:endpoint("lumen")
M.components = { ["d2440f27-52c9"] = main.entry, ["0aaa1111-0000"] = spare.entry }
M.resize(160, 50)

run(writeCfg("nolens", ""), 10)
check(#net.sent == 0, "no lensPort: nothing is sent")

cfgPath = writeCfg("lens", 'lensPort = 4243, lensNode = "power-room", lensToken = "lens-s", names = { d2440f27 = "Main" },')
local hello = codec.encoder{ node = "hub", role = "hub", boot = 1, token = "lens-s" }:hello()[1]
run(cfgPath, 330, function(n)
  if n == 3 then return { "modem_message", "lumen", "hub", 4243, 0, hello } end
end)
local msgs = {}
while true do
  local ev = net.pop(hub)
  if not ev then break end
  local msg = codec.decode(ev[6], "lens-s")
  check(msg ~= nil, "every packet is lens/1 with the LENS token")
  msgs[#msgs + 1] = msg
end
check(msgs[1].kind == "describe" and msgs[1].node == "power-room" and msgs[1].role == "lumen"
  and msgs[1].metrics.lumen_fill_ratio.unit == "0..1", "describes itself first, as lensNode")
local describes, snaps = 0, {}
for _, msg in ipairs(msgs) do
  if msg.kind == "describe" then describes = describes + 1 elseif msg.kind == "snapshot" then snaps[#snaps + 1] = msg end
end
check(describes == 2, "a hello is answered with a describe")
local s = snaps[#snaps]
local function sample(name, lsc)
  for _, x in ipairs(s.samples) do if x[1] == name and x[3] and x[3].lsc == lsc then return x[2] end end
end
check(sample("lumen_stored_eu", "Main") == 10773450724 and sample("lumen_capacity_eu", "Main") == 11340000000
  and math.abs(sample("lumen_fill_ratio", "Main") - 0.95003) < 1e-4, "stored, capacity, fill per LSC")
check(sample("lumen_net_eut", "Main") == 820 and sample("lumen_input_eut", "Main") == 65536
  and math.abs(sample("lumen_full_seconds", "Main") - 37512) < 1e-6, "flows and time to full")
check(sample("lumen_lsc_up", "LSC 0aaa") == 1 and sample("lumen_empty_seconds", "LSC 0aaa") == 1800, "time to empty")
check(math.abs(sample("lumen_drain_seconds", "LSC 0aaa") - 4e8 / 12000 / 20) < 1e-6 and sample("lumen_net_1h_eut", "LSC 0aaa") == -12000
  and sample("lumen_drain_seconds", "Main") == nil, "time to empty at the 1 hour net, and that net; nothing when not draining")
check(s.health == "bad" and #s.alerts == 2, "health and alerts go to LENS too")
check(M.find("LENS port 4243 as power-room", 1), "the header says it reports to LENS")

-- The vendored LENS modules are LENS's, byte for byte (tools/sync-lens.sh copies them).
local function read(p) local f = io.open(p); if not f then return nil end; local t = f:read("*a"); f:close(); return t end
for _, mod in ipairs({ "metrics", "codec" }) do
  local theirs = read(H.ROOT .. "/../lens/lib/lens/" .. mod .. ".lua")
  if theirs then
    check(read(H.ROOT .. "/lib/lumen/lens/" .. mod .. ".lua") == theirs,
      "lib/lumen/lens/" .. mod .. ".lua matches ../lens (run tools/sync-lens.sh)")
  end
end
M.modem = nil

H.done()
