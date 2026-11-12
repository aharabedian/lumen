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

H.done()
