-- test_lsc.lua: lumen.lsc reads an LSC's getSensorInformation lines, exactly as lumen-discover --read showed
-- them from a real one (2026-11-12).
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local check = H.check
local lsc = require("lumen.lsc")

local P = "kekztech.infodata.lapotronic_super_capacitor."
local REAL = {
  "kekztech.infodata.operational_data",
  P .. "eu_stored\\\\10,773,450,724",
  P .. "eu_stored\\\\1.08x10^10",
  P .. "used_capacity\\\\95.00%",
  P .. "total_capacity\\\\11,340,000,000",
  P .. "total_capacity\\\\1.13x10^10",
  P .. "passive_loss\\\\65",
  P .. "eu_in\\\\0",
  P .. "eu_out\\\\512",
  P .. "avg_eu_in.sec\\\\65,536\\\\5",
  P .. "avg_eu_out.sec\\\\64,716\\\\5",
  P .. "avg_eu_in.min5\\\\66,082",
  P .. "avg_eu_out.min5\\\\65,712",
  P .. "avg_eu_in.hour1\\\\42,420",
  P .. "avg_eu_out.hour1\\\\42,338",
  P .. "time_to.full\\\\10.42 hours",
  "kekztech.infodata.multi.maintenance_status.ok",
  P .. "wireless_mode.disabled",
  P .. "capacitors\\\\§4§nUHV§r\\\\0",
  P .. "capacitors\\\\§5§nUEV§r\\\\0",
  P .. "capacitors\\\\§1§l§nUIV§r\\\\0",
  P .. "capacitors\\\\§c§l§nUMV§r\\\\0",
  P .. "wireless_eu\\\\§c0",
  P .. "wireless_eu\\\\§c0",
}

local i = lsc.parse(REAL)
check(i.stored == 10773450724 and math.type(i.stored) == "integer", "stored: the exact line, commas gone, an integer")
check(i.capacity == 11340000000, "capacity: the exact line, not the 1.13x10^10 one")
check(i.used == 95.0, "used percent")
check(i.passiveLoss == 65 and i.inNow == 0 and i.outNow == 512, "passive loss, eu in/out now")
check(i.avgIn.sec == 65536 and i.avgIn.window == 5 and i.avgIn.min5 == 66082 and i.avgIn.hour1 == 42420,
  "input averages, and the seconds the first one covers")
check(i.avgOut.sec == 64716 and i.avgOut.min5 == 65712 and i.avgOut.hour1 == 42338, "output averages")
check(i.timeTo.to == "full" and i.timeTo.text == "10.42 hours" and math.abs(i.timeTo.seconds - 37512) < 1e-6,
  "time to full, as text and seconds")
check(i.maintenance == "ok" and i.wireless == "disabled", "maintenance and wireless mode")
check(i.capacitors.UHV == 0 and i.capacitors.UEV == 0 and i.capacitors.UIV == 0 and i.capacitors.UMV == 0,
  "capacitor counts, formatting codes dropped")
check(i.wirelessEu == 0, "wireless EU")
check(#i.unknown == 0, "every real line understood")

-- What we haven't seen yet still reads sensibly.
local j = lsc.parse({
  P .. "eu_stored\\\\123,456,789,012,345,678,901,234",
  P .. "time_to.empty\\\\3 days",
  P .. "time_to.empty\\\\forever",
  "kekztech.infodata.multi.maintenance_status.needs_work",
  "something.new\\\\42",
})
check(j.stored and j.stored > 1.2e23 and math.type(j.stored) == "float", "beyond an integer: a float, not nil")
check(j.timeTo.to == "empty" and j.timeTo.text == "forever" and j.timeTo.seconds == nil, "a time we can't read keeps its text")
check(j.maintenance == "needs_work", "a maintenance problem shows as its key's last word")
check(j.unknown[1] == "something.new\\\\42" and j.capacity == nil, "unknown lines kept; missing fields nil")
check(next(lsc.parse(nil).unknown) == nil, "no lines: an empty reading")

H.done()
