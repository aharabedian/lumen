-- test_discover.lua: lumen-discover lists components and their docs into a file, skips the basics unless asked,
-- filters by type, and --read calls only read-only methods (get/is/has, no arguments), showing tables, numbers
-- (integer or float), errors, and what it didn't call.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local discover = require("lumen.discover")

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
-- An IC2 reactor as seen in game (2026-11-14): its methods and docs; producing when its redstone OR the
-- setActive flag is on; a transposer sees it as "blockGenerator" (18 slots with no chambers), each part's
-- damage its heat, and each transposer call takes a tick. getSlotInfo(x, y)'s answer and getAllStacks'
-- shape (an iterator with getAll) are guesses.
local reactor = { redstone = true, flag = false, heat = 0, setCalls = {} }
local function producing() return reactor.redstone or reactor.flag end
local vent = { name = "IC2:reactorVentGold", label = "Overclocked Heat Vent", damage = 590, maxDamage = 10000, size = 1 }
local rod = { name = "gregtech:gt.rodUranium4", label = "Quad Fuel Rod (Uranium)", damage = 1, maxDamage = 100, size = 1 }
M.components["rea00000-0000"] = { type = "reactor", methods = {
    getHeat = "function():number -- Get the reactor's heat.",
    getMaxHeat = "function():number -- Get the reactor's maximum heat before exploding.",
    getOfferedEnergy = "",
    getReactorEUOutput = "function():number -- Get the reactor's base EU/t value.",
    getReactorEnergyOutput = "function():number -- Get the reactor's energy output. Not multiplied with the base EU/t value.",
    getSlotInfo = "function(x:int,y:int):table -- Get information about the item stored in the given reactor slot.",
    producesEnergy = "function():boolean -- Get whether the reactor is active and supposed to produce energy.",
    setActive = "function(active:boolean): boolean -- activate or deactivate the reactor",
  },
  proxy = {
    getHeat = function() return reactor.heat end,
    getMaxHeat = function() return 10000 end,
    getOfferedEnergy = function() return producing() and 1200.0 or 0.0 end,
    getReactorEUOutput = function() return producing() and 1200.0 or 0.0 end,
    getReactorEnergyOutput = function() return 0.0 end,
    getSlotInfo = function(x, y)
      if y == nil then return nil end -- one argument: nothing (seen in game)
      if x > 8 or y > 5 then error("invalid slot") end
      if x == 0 and y == 0 then return { item = vent.label, heat = vent.damage } end
    end,
    producesEnergy = function() return producing() end,
    setActive = function(on) reactor.setCalls[#reactor.setCalls + 1] = on; reactor.flag = on; return true end,
  } }
local stacks = { [5] = { [1] = vent, [3] = vent, [5] = rod, [14] = rod } }
local tcalls = {}
local function tick() M.time = M.time + 0.05 end
local function tr(name, f) return function(...) tcalls[name] = (tcalls[name] or 0) + 1; tick(); return f(...) end end
M.components["tra00000-0000"] = { type = "transposer", methods = {}, proxy = {
    getInventoryName = tr("getInventoryName", function(side)
      return ({ [4] = "tile.IronChest", [5] = "blockGenerator" })[side]
    end),
    getInventorySize = tr("getInventorySize", function(side) return ({ [4] = 54, [5] = 18 })[side] end),
    getStackInSlot = tr("getStackInSlot", function(side, slot) return stacks[side] and stacks[side][slot] end),
    getAllStacks = tr("getAllStacks", function(side)
      local all = {}
      for slot = 1, ({ [4] = 54, [5] = 18 })[side] do all[slot] = (stacks[side] or {})[slot] or {} end
      return { getAll = function() return all end }
    end),
    transferItem = tr("transferItem", function() error("moved an item") end),
  } }

ok, out, file = run("--probe")
check(ok and file:find("== reactor rea00000-0000 (reactor)\n  getHeat  function():number", 1, true)
  and file:find("  setActive  function(active:boolean): boolean", 1, true), "--probe lists the reactor's methods with docs" .. (ok and "" or tostring(out)))
check(file:find("producesEnergy() -> true", 1, true) and file:find("getOfferedEnergy() -> 1200", 1, true),
  "it reads producesEnergy and getOfferedEnergy, which --read skips")
check(file:find('getSlotInfo(0, 0) -> { heat=590 (integer), item="Overclocked Heat Vent" }', 1, true)
  and file:find("getSlotInfo(0..9, 0..6): 1 answered (first 6 shown), 16 errors (first: getSlotInfo(9, 0): ", 1, true),
  "getSlotInfo(x, y) is tried for every column and row; answers shown, errors counted")
check(file:find('side 5 (east): "blockGenerator", 18 slots', 1, true)
  and file:find("side 2 (north): no inventory", 1, true), "each transposer side: inventory name and size, or none")
check(file:find('[1] { damage=590 (integer), label="Overclocked Heat Vent", maxDamage=10000 (integer), name="IC2:reactorVentGold", size=1 (integer) }', 1, true)
  and file:find("[3] Overclocked Heat Vent, damage 590/10000", 1, true), "every field of the first stack of a kind; the rest short")
check(file:find("4 filled; 18 getStackInSlot calls took 0.90 s", 1, true), "reading a side is timed")
check(file:find("getAllStacks: table, 18 entries, 0.05 s", 1, true), "and getAllStacks, once, timed")
check(tcalls.transferItem == nil and #reactor.setCalls == 0, "--probe moves nothing and never calls setActive")
check(discover.isReactorInventory("blockGenerator") and not discover.isReactorInventory("tile.IronChest"),
  "a transposer's blockGenerator side is the reactor")

-- --pause on a reactor its redstone runs: setActive can't stop it; put back with setActive(false).
ok, _, file = run("--probe", "--pause")
check(ok and file:find("still producing: its redstone runs it", 1, true) and reactor.flag == false
  and reactor.setCalls[#reactor.setCalls] == false and file:find("put back: setActive(false), its redstone runs it", 1, true),
  "--pause on a reactor redstone runs: can't stop it; left to its redstone, not held on by setActive")
-- --pause on a reactor setActive runs: paused, then started again.
reactor.redstone, reactor.flag, reactor.setCalls = false, true, {}
ok, _, file = run("--pause")
check(ok and file:find("paused 5 ", 1, true) and file:find("producing=false parts damage=1182", 1, true),
  "it reads heat, output and parts damage while paused")
check(reactor.flag == true and producing() and file:find("it ran on setActive alone, so it's started again", 1, true)
  and file:find("after .-producing=true"), "a reactor that ran on setActive alone is started again")
-- Off: left alone.
reactor.flag, reactor.setCalls = false, {}
ok, _, file = run("--pause")
check(ok and #reactor.setCalls == 0 and file:find("pause test skipped: the reactor isn't producing", 1, true),
  "a reactor that's off is left alone")
-- Interrupted while paused: still put back.
reactor.flag = true
local realSleep = os.sleep -- luacheck: ignore 143
local sleeps = 0
os.sleep = function(t) sleeps = sleeps + 1; if sleeps == 2 then error("interrupted") end; realSleep(t) end -- luacheck: ignore 142
ok, _, file = run("--pause")
os.sleep = realSleep -- luacheck: ignore 142
check(ok and reactor.flag == true and file:find("pause test failed: .-interrupted"),
  "a failure while paused still puts the reactor back")

H.done()
