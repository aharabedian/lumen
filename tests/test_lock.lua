-- test_lock.lua: who can switch (operators). Listed players can tap AUTO / ON / OFF, RESET and QUIT; anyone else's
-- tap changes nothing, says who can, and goes in the log with their name. Looking around (pages, TILES / ROWS,
-- BIG) stays open to all. lumen-setup's GENERAL tab sets it.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local Gen = require("gen")
local check = H.check
local config = require("lumen.config")
local log = require("lumen.log")

check(config.check({ operators = { "Steve", "Alex" } }), "operators: a list of names")
check(not config.check({ operators = "Steve" }), "not a name on its own")

local lsc = LSC.new{ stored = 6e9, capacity = 1e10, inSec = 0, outSec = 1000, in1h = 1000, out1h = 1000 }
local rs = Gen.redstone()
M.components = { ["d2440f27-52c9"] = lsc.entry, ["c0010000-0000"] = rs.entry }
local cfgPath = H.TMP .. "/lumen.cfg"
local fh = assert(io.open(cfgPath, "w"))
fh:write([[return {
  glanceAfter = 0, operators = { "Steve", "Alex" },
  control = { { name = "Vac", redstone = "c001", side = "top", onBelow = 30, offAbove = 90 } },
}
]])
fh:close()
local function run(untilTime, onPull, quitter)
  M.pulls = 0
  local quitAt
  M.onPull = function(n)
    local e = onPull and onPull(n, M.time)
    if e then return e end
    if M.time >= untilTime then
      if not quitAt then quitAt = n; return { "touch", "scr", M.W - 3, 1, 0, quitter or "Steve" } end
      return { "interrupted" }
    end
  end
  local ok, err = pcall(H.run, "lumen.lua", cfgPath)
  M.onPull = nil
  check(ok, "runs without errors" .. (ok and "" or (": " .. tostring(err))))
end
local function tapAt(text, minY, minX, who)
  local x, y = M.find(text, minY, minX)
  assert(x, "nothing to tap: " .. text)
  return { "touch", "scr", x + 1, y, 0, who }
end

M.resize(160, 50)
M.setTime(0)
rs.out[1] = 15
local seen = {}
run(60, function(n)
  local _, y = M.find("Vac", 30)
  if n == 2 then return tapAt(" OFF ", y, 120, "Bob") end
  if n == 3 then seen.bob = (rs.out[1] or 0) == 15 and M.find("Only Steve and Alex can switch", 3) end
  if n == 4 then return tapAt(" TIMELINE ", 3, nil, "Bob") end
  if n == 5 then seen.look = M.find("◀ BACK", 3) ~= nil end
  if n == 6 then return tapAt("◀ BACK", 3, nil, "Bob") end
  if n == 8 then return tapAt(" OFF ", y, 120, "Steve") end
  if n == 9 then seen.steve = (rs.out[1] or 0) == 0 end
  if n == 10 then return { "touch", "scr", M.W - 3, 1, 0, "Bob" } end           -- QUIT
  if n == 11 then seen.noQuit = M.find("Only Steve and Alex can switch", 3) ~= nil end
end, "Alex")
check(seen.bob, "Bob taps OFF: nothing switched, and the screen says who can")
check(seen.look, "Bob can still look around")
check(seen.steve, "Steve taps OFF: off")
check(seen.noQuit, "Bob can't QUIT either; Alex can")
local kept = log.new(H.TMP .. "/lumen-log.cfg", M.epoch + M.time)
local tried, did = false, false
for _, e in ipairs(kept.list) do
  if e.player == "Bob" and e.text:find("locked", 1, true) then tried = true end
  if e.player == "Steve" and e.kind == "HAND" and e.text:find("set OFF", 1, true) then did = true end
end
check(tried and did, "the log: Bob's tries (locked) and Steve's OFF, each with who")

H.done()
