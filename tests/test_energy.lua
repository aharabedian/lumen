-- test_energy.lua: the last 24 hours' energy. lumen.history keeping each source (output per step; per hour EU,
-- time running and read, starts, the most while running) and the LSC's in and out; lumen.energy's bands (a
-- group, the sources not in one, and "other": what came in that no source accounts for), their EU, share,
-- uptime, starts and at full; HEADROOM; history from 0.2.1 (no in and out kept) still loading; then the ENERGY
-- page in lumen at 160 x 33 and 80 x 25.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local Gen = require("gen")
local check = H.check
local history = require("lumen.history")
local energy = require("lumen.energy")

local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 0.01) * math.max(1, math.abs(b)) end

---------------------------------------------------------------- three hours, kept
local h = history.new()
local T0 = 1800000000 - (1800000000 % 3600)          -- on the hour
local srcs = {
  { name = "N-1", ok = true, active = true, output = 43600 },
  { name = "N-2", ok = true, active = false, output = 0 },
  { name = "S-6", ok = true, active = true, output = 1320 },
  { name = "LFTR", ok = true, active = true, output = 32768 },
}
local total = { name = "All LSCs", address = "", ok = true, fill = 0.7, stored = 7e9 }
local OTHER = 5000
for t = T0, T0 + 3 * 3600 - 5, 5 do
  local hour = (t - T0) // 3600
  srcs[2].active, srcs[2].output = hour == 1, hour == 1 and 43600 or 0
  local made = OTHER
  for _, s in ipairs(srcs) do
    h:source(s.name, s, t, 5)
    if s.active then made = made + s.output end
  end
  total.inEut = made
  total.outEut = (t >= T0 + 4000 and t < T0 + 4300) and 120000 or 70000
  h:add("", total, t, 5)
end
local now = T0 + 3 * 3600 - 5
local d1 = h:sourceDay("N-1", now)
check(near(d1.eu, 43600 * 20 * (3 * 3600 - 5), 0.002) and near(d1.on, 3 * 3600 - 5) and d1.starts == 0 and d1.max == 43600,
  "a source's 24 h: EU, time running, the most while running; running from the first reading isn't a start")
local d2 = h:sourceDay("N-2", now)
check(near(d2.on, 3600) and d2.starts == 1 and near(d2.seen, 3 * 3600 - 5), "N-2 ran one hour: one start, read for three")

local groups = { { name = "Quad Uranium", members = { { name = "Reactor N-1", source = "N-1" }, { name = "Reactor N-2", source = "N-2" } } } }
local m = { total = total, lscs = { total }, sources = srcs, groups = groups }
local e = energy.day(h, now, m)
local names = {}
for _, b in ipairs(e.bands) do names[#names + 1] = b.name end
check(table.concat(names, ",") == "Quad Uranium,S-6,LFTR,other", "bands: the group, the sources not in it, then other")
local q, other = e.bands[1], e.bands[4]
check(near(q.eu, d1.eu + d2.eu) and q.starts == 1 and near(q.on, (3 * 3600 - 5 + 3600) / (2 * (3 * 3600 - 5)))
  and near(q.avgOn, 43600) and q.full == 87200 and q.members == 2,
  "the group: its members' EU and starts, uptime together, EU/t per member while running, at full added up")
check(near(other.eu, OTHER * 20 * (3 * 3600 - 5), 0.01) and other.kind == "other", "other: what came in that no source made")
local shares = 0
for _, b in ipairs(e.bands) do shares = shares + b.share end
check(near(shares, 1, 0.005), "the shares add up")
local someI
for i, v in pairs(q.samples) do if v > 40000 then someI = i end end
check(someI and near(e.came[someI], q.samples[someI] + 1320 + 32768 + OTHER, 0.01) and e.load[someI],
  "per step: each band's EU/t, what came in and went out")
local hr = e.headroom
check(hr.full == 87200 + 1320 + 32768 and hr.peak == 120000 and near(hr.spare, 87200 + 1320 + 32768 - 120000)
  and hr.unit.name == "Quad Uranium" and hr.unit.each == 43600, "headroom: everything at full against the peak, in reactors")
check(near(hr.avg, 70000, 0.05) and hr.making == 43600 + 1320 + 32768, "the average load, and what's making now")

-- Kept across a restart, and history from 0.2.1 (no in and out) still loads.
local h2 = history.new(require("serialization").unserialize(require("serialization").serialize(h:save())))
check(near(h2:sourceDay("N-1", now).eu, d1.eu) and #h2:sourceChart("N-1") > 0 and #h2:flows("") > 0, "saved and loaded")
-- As 0.2.1 saved it: no in and out, and the sample being averaged (cur) without them either.
local old = require("serialization").unserialize(require("serialization").serialize(h:save()))
old.src = nil
for key in pairs(old.hours) do if key:find("^source:") then old.hours[key] = nil end end
for _, l in pairs(old.lsc) do
  for _, rg in ipairs(l) do
    rg.inE, rg.outE = nil, nil
    if rg.cur then rg.cur.inE, rg.cur.outE = nil, nil end
  end
end
local crashed = require("serialization").unserialize(require("serialization").serialize(old))
local h3 = history.new(old)
local f3 = h3:flows("")
check(#f3 > 0 and f3[1].inE == false, "0.2.1's history: in and out unknown for what was kept, nothing breaks")
local okAdd, errAdd = pcall(function()
  for t = now + 600, now + 1800, 5 do h3:add("", total, t, 5) end   -- restarted after its sample ended, as in game
end)
check(okAdd, "the next readings finish 0.2.1's half-done sample (seen in game: it crashed)" .. (okAdd and "" or (": " .. tostring(errAdd))))
local rg3 = h3.lsc[""][3]
check(#rg3.inE == #rg3.i and rg3.inE[#rg3.inE] and rg3.inE[#rg3.inE] > 0, "in and out line up with the samples, the new ones known")
-- A file saved after that crash: one more sample than in and out (the push stopped half way).
for _, l in pairs(crashed.lsc) do
  local rg = l[3]
  rg.inE, rg.outE = {}, {}
  for j = 1, #rg.i - 1 do rg.inE[j], rg.outE[j] = false, false end
  rg.cur = nil
end
local h4 = history.new(crashed)
local rg4 = h4.lsc[""][3]
check(#rg4.inE == #rg4.i and #rg4.outE == #rg4.i, "a file saved after that crash: in and out lined up again")
check(#energy.day(h3, now, m).bands == 3, "and the page builds without sources' history, claiming no \"other\"")

---------------------------------------------------------------- the page, in lumen
local CAP = 2e10
local lsc = LSC.new{ stored = 0.6 * CAP, capacity = CAP, inSec = 0, outSec = 60000, in1h = 60000, out1h = 60000 }
local rs, reactors = {}, {}
M.components = { ["d2440f27-52c9"] = lsc.entry }
for k = 1, 5 do
  rs[k] = Gen.redstone()
  reactors[k] = Gen.reactor{ heat = 1000, maxHeat = 10000, output = k == 5 and 1320 or 43600, produces = false }
  M.components[("c%03d0000-0000"):format(k)] = rs[k].entry
  M.components[("e%03d0000-0000"):format(k)] = reactors[k].entry
end
local lftr = Gen.gt("gtpp.multimachine.lftr", { active = true, lines = { "Current Output: 32,768 EU/t" } })
M.components["a1b20000-0000"] = lftr.entry
local cfgPath = H.TMP .. "/lumen.cfg"
local fh = assert(io.open(cfgPath, "w"))
fh:write([[return {
  heatWarn = 95, heatBad = 98, glanceAfter = 0,
  sources = { { address = "e001", name = "N-1" }, { address = "e002", name = "N-2" }, { address = "e003", name = "N-3" },
    { address = "e004", name = "N-4" }, { address = "e005", name = "S-6" }, { address = "a1b2", name = "LFTR" } },
  groups = { { name = "Quad Uranium", steps = { { onBelow = 75, offAbove = 90, run = 2 } } } },
  control = {
    { name = "Reactor N-1", redstone = "c001", side = "top", group = "Quad Uranium", source = "N-1" },
    { name = "Reactor N-2", redstone = "c002", side = "top", group = "Quad Uranium", source = "N-2" },
    { name = "Reactor N-3", redstone = "c003", side = "top", group = "Quad Uranium", source = "N-3" },
    { name = "Reactor N-4", redstone = "c004", side = "top", group = "Quad Uranium", source = "N-4" },
    { name = "Reactor S-6", redstone = "c005", side = "top", always = true, source = "S-6" },
  },
}
]])
fh:close()
local function step()
  local made = 32768 + 4000
  for k = 1, 5 do
    local on = (rs[k].out[1] or 0) > 0
    reactors[k].state.produces = on
    if on then made = made + reactors[k].state.output end
  end
  lsc.state.inSec, lsc.state.in5m = made, made
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
local function tapAt(text, minY)
  local x, y = M.find(text, minY)
  assert(x, "nothing to tap: " .. text)
  return { "touch", "scr", x + 1, y, 0, "p" }
end

-- A day already kept (as lumen.state saves it): the four reactors taking turns by two, the breeder always on,
-- the LFTR stopping an hour for maintenance, 4k EU/t from somewhere unlisted, and a load that swings by day.
M.setTime(0)
do
  local day, NOW = history.new(), M.epoch
  local tot = { name = "LSC d244", address = "d2440f27-52c9", ok = true, fill = 0.6, stored = 1.2e10 }
  for t = NOW - 86400 + 5, NOW, 5 do
    local hours = (t - (NOW - 86400)) / 3600
    local load = 70000 + 30000 * math.sin(hours / 24 * 2 * math.pi) + ((math.floor(hours * 3) % 7 == 0) and 25000 or 0)
    local made = 4000
    for k = 1, 4 do
      local on = math.floor(hours / 3 + (k - 1) / 2) % 2 == 0
      day:source("N-" .. k, { ok = true, active = on, output = on and 43600 or 0 }, t, 5)
      if on then made = made + 43600 end
    end
    day:source("S-6", { ok = true, active = true, output = 1320 }, t, 5)
    local lftrOn = not (hours >= 13 and hours < 14)
    day:source("LFTR", { ok = true, active = lftrOn, output = lftrOn and 32768 or 0 }, t, 5)
    made = made + 1320 + (lftrOn and 32768 or 0)
    tot.inEut, tot.outEut = made, load
    day:add(tot.address, tot, t, 5)
  end
  require("lumen.state").save(H.TMP .. "/lumen-state.cfg", { saved = NOW, history = day:save() })
end

M.resize(160, 50)
M.aspect = { 7, 3 }
run(600)                                    -- ten minutes on top of the day kept
local seen = {}
run(M.time + 30, function(n)
  if n == 2 then return tapAt(" ENERGY ", 3) end
  if n == 4 then
    seen.page = M.find("◀ BACK", 3) and M.find("ENERGY", 3) and M.find("MADE, 24 H", 3) and M.find("load (out)", 3)
    seen.rows = M.find("Quad Uranium (4)", 3) and M.find("S-6", 3) and M.find("LFTR", 3) and M.find("other (no source)", 3)
    seen.headroom = M.find("HEADROOM", 3) and M.find("spare at the peak", 3) and M.find("Quad Uranium reactors", 3)
    seen.oob = M.oob
    H.screen("lumen-energy")
  end
  if n == 5 then return tapAt("◀ BACK", 3) end
  if n == 7 then seen.back = M.find("POWER", 3) ~= nil end
end)
check(seen.page, "ENERGY: a day kept across a restart: the chart, its legend and the load line")
check(seen.rows, "a row for the group, each source not in it, and other")
check(seen.headroom, "HEADROOM, spare at the peak in Quad Uranium reactors")
check(seen.oob == 0, "fits the 7 x 3 wall")
check(seen.back, "BACK: the main page")

M.aspect = nil
M.resize(80, 25)
M.oob = 0
seen = {}
run(M.time + 20, function(n)
  if n == 2 then return tapAt(" ENERGY ", 3) end
  if n == 4 then
    seen.page = M.find("HEADROOM", 3) and M.find("spare at the peak", 3) and M.find("Quad Uranium (4)", 3) and M.oob == 0
    H.screen("lumen-energy-tier2")
  end
end)
check(seen.page, "tier 2: the page fits, chart, table and headroom")
M.resize(160, 50)

H.done()
