-- test_history.lua: lumen.history (fill at three ranges, the net over a window, hourly totals for the last 24
-- hours and the 24 before, switches' time on) and lumen.state (the clock, keeping it all across a restart).
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local history = require("lumen.history")
local state = require("lumen.state")

local h = history.new()
local T0 = 1.8e9
-- 30 hours of readings every 5 s: half full and filling at +1000 EU/t (in 3000, out 2000), with one big draw.
local stored, cap = 5e9, 1e10
local t = T0
while t < T0 + 30 * 3600 do
  local out = (t == T0 + 29 * 3600) and 900000 or 2000
  h:add("d244", { ok = true, fill = stored / cap, stored = stored, inEut = 3000, outEut = out }, t, 5)
  h:switch("Vac nuke", t < T0 + 3600, t, 5)
  stored = stored + 1000 * 20 * 5
  t = t + 5
end
local now = t - 5

local c1, c3 = h:chart("d244", 1), h:chart("d244", 3)
check(#c1 == history.SAMPLES + 1 and #c3 == history.SAMPLES + 1, "each range keeps its samples (and the one being filled)")
check(c1[#c1] > c1[1] and c3[#c3] > c3[1], "charts rise while filling")
local span1 = (#c1 - 1) * 30
check(span1 == 4800, "80 minutes at 30 s")
local rate = h:rate("d244", 600, now)
check(rate and math.abs(rate - 1000) < 30, ("the net over the last 10 minutes: +1000 EU/t (%s)"):format(tostring(rate)))
check(h:rate("d244", 6 * 3600, now) == nil, "no rate past what the 30 s samples cover")
check(h:rate("nope", 600, now) == nil, "no rate for an LSC with no history")

local d = h:day("d244", now)
check(d.hours == 24, "the last 24 hours")
check(math.abs(d.inEu - 3000 * 20 * 86400) / d.inEu < 0.001, "EU in: 3000 EU/t for a day")
check(d.peakOut == 900000 and d.peakAt == T0 + 29 * 3600, "the highest draw, and when")
check(d.minFill and d.minFill > 0.5, "the lowest fill of the day")
local before = h:day("d244", now - 86400)
check(before.hours == 6 and before.on["Vac nuke"] == 3600, "the 24 h before: 6 hours of readings, the switch on its first hour")
check((d.on["Vac nuke"] or 0) == 0, "and off since")

h:keep({ x = true })
check(#h:chart("d244", 1) == 0 and h:day("d244", now).hours == 0 and before.on["Vac nuke"], "forgets LSCs that are gone, keeps switches")

---------------------------------------------------------------- state: the clock, saving, loading
local fs, computer = require("filesystem"), require("computer")
M.setTime(100)
local clock = state.clock(fs, computer, H.TMP .. "/clock")
check(math.abs(clock:now() - (M.epoch + 100)) < 1 and clock.real, "the clock: real seconds, from a file's time")
M.setTime(160)
check(math.abs(clock:now() - (M.epoch + 160)) < 1, "carried on with uptime")
M.noClock = true
local c2 = state.clock(fs, computer, H.TMP .. "/clock2")
check(c2:now() == 160 and not c2.real, "no file time: uptime, and it says so")
M.noClock = nil

local h2 = history.new()
h2:add("d244", { ok = true, fill = 0.5, stored = 5, inEut = 1, outEut = 1 }, T0, 5)
h2:add("d244", { ok = true, fill = 0.6, stored = 6, inEut = 1, outEut = 1 }, T0 + 31, 5)
local path = H.TMP .. "/lumen-state.cfg"
check(state.save(path, { saved = T0, modes = { ["Vac nuke"] = "off" }, history = h2:save() }), "saves")
local back = state.load(path)
check(back.modes["Vac nuke"] == "off" and back.saved == T0, "loads what it saved")
local h3 = history.new(back.history)
check(#h3:chart("d244", 1) == 2 and h3:chart("d244", 1)[1] == 0.5, "history comes back")
check(next(state.load(H.TMP .. "/none.cfg")) == nil, "no file: nothing")
local f = io.open(H.TMP .. "/junk.cfg", "w"); f:write("{{{"); f:close()
check(next(state.load(H.TMP .. "/junk.cfg")) == nil, "a broken file: nothing")

H.done()
