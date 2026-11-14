-- test_discover.lua: lumen-discover lists components and their docs into a file, skips the basics unless asked,
-- filters by type, and --read calls only read-only methods (get/is/has, no arguments), showing tables, numbers
-- (integer or float), errors, and what it didn't call.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check

local calls = {}
local function method(name, value)
  return function(...)
    calls[name] = (calls[name] or 0) + 1
    if select("#", ...) > 0 then error("called with arguments") end
    if type(value) == "function" then return value() end
    return value
  end
end

-- An LSC, with the methods (and docs) lumen's first in-game look found, a few of them.
M.components = {
  ["gp000000-0000"] = { type = "gpu", methods = { set = "function(x, y, value) -- write text" } },
  ["lsc00000-0000"] = { type = "gt_machine", methods = {
      getStoredEUString = "function():string --  Returns the amount of electricity contained in this Block",
      getEUStored = "function():number; Returns the EU stored in this block",
      getEUInputAverage = "function():number; Returns the average EU input of this block",
      getSensorInformation = "function():table; Returns sensor information about this block",
      isMachineActive = "function():boolean; Returns whether the machine is currently active",
      hasWork = "function():boolean; Returns true if the machine currently has work to do",
      getCoordinates = "function():table; Returns machine coordinates",
      getName = "function():string; Returns the machine's name",
      setWorkAllowed = "function(work:boolean); Sets whether this block is currently allowed to work",
      getOwnerName = "function():string; Returns the name of this block's owner",
    },
    proxy = {
      getStoredEUString = method("getStoredEUString", "10773000000000"),
      getEUStored = method("getEUStored", 9223372036854775807),
      getEUInputAverage = method("getEUInputAverage", 251.5),
      getSensorInformation = method("getSensorInformation", { "Used Capacity: §a10,773,000,000,000§r EU", "Avg EU IN: 251" }),
      isMachineActive = method("isMachineActive", true),
      hasWork = method("hasWork", false),
      getCoordinates = method("getCoordinates", function() return -2216, 85, 649 end),
      getName = method("getName", "multimachine.supercapacitor"),
      setWorkAllowed = method("setWorkAllowed", nil),
      getOwnerName = method("getOwnerName", function() error("no owner") end),
    } },
}

local prefix = H.TMP .. "/root"
os.execute('mkdir -p "' .. prefix .. '/home"')
local realGetenv = os.getenv
os.getenv = function(k) if k == "LUMEN_PREFIX" then return prefix end return realGetenv(k) end

local function run(...)
  local lines, realPrint = {}, print
  print = function(...) lines[#lines + 1] = table.concat({ ... }, "\t") end
  local ok, err = pcall(H.run, "lumen-discover.lua", ...)
  print = realPrint
  local f = io.open(prefix .. "/home/lumen-discover.txt")
  local file = f and f:read("*a") or ""
  if f then f:close() end
  return ok, table.concat(lines, "\n"), file, err
end

local ok, out, file, err = run()
check(ok, "runs" .. (ok and "" or (": " .. tostring(err))))
check(out:find("gt_machine%s+lsc00000%-0000 %(10 methods%)") and out:find("gpu%s+gp000000%-0000\n"),
  "prints every component; the basics without their methods")
check(file:find("== gt_machine lsc00000-0000\n  getCoordinates  function():table", 1, true)
  and not file:find("== gpu", 1, true), "the file has each method, sorted, with its doc; basics only with --all")
local _
ok, _, file = run("--all")
check(ok and file:find("== gpu gp000000-0000", 1, true), "--all details the basics too")
ok, out, file = run("gpu")
check(ok and file:find("== gpu", 1, true) and not file:find("== gt_machine", 1, true) and out:find("gt_machine", 1, true),
  "a filter details only matching types, but still lists everything")

---------------------------------------------------------------- --read
calls = {}
ok, out, file = run("--read")
check(ok and file:find('getStoredEUString -> "10773000000000"', 1, true), "--read: strings, quoted")
check(file:find("getEUStored -> 9223372036854775807 (integer)", 1, true)
  and file:find("getEUInputAverage -> 251.5 (float)", 1, true), "numbers exactly, saying integer or float")
check(file:find("getSensorInformation -> table\n    [1] \"Used Capacity: §a10,773,000,000,000§r EU\"\n    [2] \"Avg EU IN: 251\"", 1, true),
  "tables get a line per entry, formatting codes and all")
check(file:find("isMachineActive -> true", 1, true) and file:find("hasWork -> false", 1, true), "booleans")
check(file:find("getCoordinates -> -2216 (integer), 85 (integer), 649 (integer)", 1, true), "several results")
check(file:find("getOwnerName -> error: ", 1, true), "a method that fails is reported, and the rest still read")
check(calls.setWorkAllowed == nil and file:find("not called (may change something, or take arguments): setWorkAllowed", 1, true),
  "setWorkAllowed is never called, and the report says so")
check(out:find("getStoredEUString", 1, true), "the readings are printed too")
ok, out = run("--read", "nothing_here")
check(ok and out:find("no nothing_here component found", 1, true), "--read of a type that isn't attached says so")

---------------------------------------------------------------- --probe
-- A reactor with the methods lumen-discover found in game (2026-11-14); getSlotInfo's and setActive's
-- arguments and answers are guesses. A transposer with the reactor on top and a chest of cells below.
local reactor = { heat = 120, active = true, setCalls = {} }
local cell = { name = "IC2:reactorCoolantSix", label = "60k Coolant Cell", damage = 40, maxDamage = 10000, size = 1 }
M.components["rea00000-0000"] = { type = "reactor", methods = {
    getHeat = "function():number -- Get the reactor's heat.",
    getMaxHeat = "function():number -- Get the reactor's maximum heat before exploding.",
    getReactorEUOutput = "function():number -- Get the reactor's energy output.",
    getReactorEnergyOutput = "function():number -- Get the reactor's energy output.",
    getOfferedEnergy = "function():number",
    getSlotInfo = "function(slot:number):table",
    producesEnergy = "function():boolean -- Get whether the reactor is active and supposed to produce energy.",
    setActive = "function(active:boolean)",
  },
  proxy = {
    getHeat = function() return reactor.heat end,
    getMaxHeat = function() return 10000 end,
    getReactorEUOutput = function() return reactor.active and 1240.0 or 0.0 end,
    getReactorEnergyOutput = function() return 0.0 end,
    getOfferedEnergy = function() return 0.0 end,
    getSlotInfo = function(n)
      if n < 1 or n > 54 then error("invalid slot") end
      if n == 3 then return { item = cell.label, damage = cell.damage } end
    end,
    producesEnergy = function() return reactor.active end,
    setActive = function(on) reactor.setCalls[#reactor.setCalls + 1] = on; reactor.active = on end,
  } }
local stacks = { [1] = { [3] = cell, [4] = cell }, [0] = { [1] = cell } }
local tcalls = {}
local function tr(name, f) return function(...) tcalls[name] = (tcalls[name] or 0) + 1; return f(...) end end
M.components["tra00000-0000"] = { type = "transposer", methods = {}, proxy = {
    getInventoryName = tr("getInventoryName", function(side)
      return ({ [0] = "minecraft:chest", [1] = "blockReactorChamber" })[side]
    end),
    getInventorySize = tr("getInventorySize", function(side) return ({ [0] = 27, [1] = 54 })[side] end),
    getStackInSlot = tr("getStackInSlot", function(side, slot)
      M.time = M.time + 0.05 -- one tick a call, as if not direct
      return stacks[side] and stacks[side][slot]
    end),
    transferItem = tr("transferItem", function() error("moved an item") end),
  } }

ok, out, file = run("--probe")
check(ok and file:find("== reactor rea00000-0000 (reactor)\n  getHeat  function():number", 1, true)
  and file:find("  setActive  function(active:boolean)", 1, true), "--probe lists the reactor's methods with docs" .. (ok and "" or tostring(out)))
check(file:find("producesEnergy() -> true", 1, true) and file:find("getOfferedEnergy() -> 0", 1, true),
  "it reads producesEnergy and getOfferedEnergy, which --read skips")
check(file:find('getSlotInfo(3) -> { damage=40 (integer), item="60k Coolant Cell" }', 1, true)
  and file:find("getSlotInfo(0..58): 1 answered, 5 errors (first: getSlotInfo(0): ", 1, true),
  "getSlotInfo is tried for each slot; answers shown, errors counted")
check(file:find('side 1 (top): "blockReactorChamber", 54 slots', 1, true)
  and file:find("side 2 (north): no inventory", 1, true), "each transposer side: inventory name and size, or none")
check(file:find('[3] { damage=40 (integer), label="60k Coolant Cell", maxDamage=10000 (integer), name="IC2:reactorCoolantSix", size=1 (integer) }', 1, true)
  and file:find("[4] 60k Coolant Cell, damage 40/10000", 1, true), "every field of the first stack of a kind; the rest short")
check(file:find("2 filled; 54 getStackInSlot calls took 2.70 s", 1, true), "reading a side is timed")
check(tcalls.transferItem == nil and #reactor.setCalls == 0, "--probe moves nothing and never calls setActive")

-- --pause: off for 5 s, read every second, back on; parts' damage from the transposer's reactor side.
ok, _, file = run("--probe", "--pause")
check(ok and #reactor.setCalls == 2 and reactor.setCalls[1] == false and reactor.setCalls[2] == true and reactor.active,
  "--pause: setActive(false), then setActive(true)")
check(file:find("paused 5 ", 1, true) and file:find("producing=false parts damage=80", 1, true)
  and file:find("resumed .-producing=true"), "it reads heat, output and parts damage while paused and after")
reactor.active = false
reactor.setCalls = {}
ok, _, file = run("--pause")
check(ok and #reactor.setCalls == 0 and file:find("pause test skipped: the reactor isn't producing", 1, true),
  "a reactor that's off is left alone (setActive(true) would start it)")
reactor.active = true
M.components["rea00000-0000"].proxy.setActive = function(on)
  reactor.setCalls[#reactor.setCalls + 1] = on
  if #reactor.setCalls == 1 then reactor.active = false end
  if on == true then reactor.active = true end
end
local realSleep = os.sleep -- luacheck: ignore 143
local sleeps = 0
os.sleep = function(t) sleeps = sleeps + 1; if sleeps == 2 then error("interrupted") end; realSleep(t) end -- luacheck: ignore 142
ok, _, file = run("--pause")
os.sleep = realSleep -- luacheck: ignore 142
check(ok and reactor.setCalls[#reactor.setCalls] == true and reactor.active
  and file:find("pause test failed: .-interrupted"), "a failure while paused still turns the reactor back on")

H.done()
