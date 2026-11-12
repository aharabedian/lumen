--[[ tests/mocks/lsc.lua - an LSC as the game shows it to OpenComputers: a gt_machine whose getName() is
  "multimachine.supercapacitor" and whose getSensorInformation() returns lines in the format seen in game
  (2026-11-12; tests/test_lsc.lua has that LSC's lines verbatim).

  local LSC = require("lsc")
  local l = LSC.new{ stored = 10773450724, capacity = 11340000000, inSec = 65536, outSec = 64716,
                     in5m = 66082, out5m = 65712, in1h = 42420, out1h = 42338,
                     timeTo = "full", timeText = "10.42 hours", maintenance = "ok" }
  M.components[addr] = l.entry     what tests/mocks/oc.lua serves; change l.state fields between readings
  l.state.broken = "chunk unloaded"   getSensorInformation raises this
  LSC.machine(name)                another gt_machine (not an LSC), named `name`
]]

local LSC = {}

local P = "kekztech.infodata.lapotronic_super_capacitor."

local function commas(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""):gsub("^%-,", "-"))
end

local function sci(n)
  local e = math.floor(math.log(math.max(n, 1), 10))
  return ("%.2fx10^%d"):format(n / 10 ^ e, e)
end

local function lines(s)
  local out = { "kekztech.infodata.operational_data" }
  local function add(l) out[#out + 1] = l end
  add(P .. "eu_stored\\\\" .. commas(s.stored))
  add(P .. "eu_stored\\\\" .. sci(s.stored))
  add(P .. ("used_capacity\\\\%.2f%%"):format(s.stored / s.capacity * 100))
  add(P .. "total_capacity\\\\" .. commas(s.capacity))
  add(P .. "total_capacity\\\\" .. sci(s.capacity))
  add(P .. "passive_loss\\\\" .. commas(s.passiveLoss or 65))
  add(P .. "eu_in\\\\0")
  add(P .. "eu_out\\\\512")
  add(P .. "avg_eu_in.sec\\\\" .. commas(s.inSec or 0) .. "\\\\5")
  add(P .. "avg_eu_out.sec\\\\" .. commas(s.outSec or 0) .. "\\\\5")
  add(P .. "avg_eu_in.min5\\\\" .. commas(s.in5m or s.inSec or 0))
  add(P .. "avg_eu_out.min5\\\\" .. commas(s.out5m or s.outSec or 0))
  add(P .. "avg_eu_in.hour1\\\\" .. commas(s.in1h or s.inSec or 0))
  add(P .. "avg_eu_out.hour1\\\\" .. commas(s.out1h or s.outSec or 0))
  if s.timeTo then add(P .. "time_to." .. s.timeTo .. "\\\\" .. (s.timeText or "")) end
  add("kekztech.infodata.multi.maintenance_status." .. (s.maintenance or "ok"))
  add(P .. "wireless_mode.disabled")
  for _, tier in ipairs({ "§4§nUHV§r", "§5§nUEV§r", "§1§l§nUIV§r", "§c§l§nUMV§r" }) do
    add(P .. "capacitors\\\\" .. tier .. "\\\\0")
  end
  add(P .. "wireless_eu\\\\§c0")
  add(P .. "wireless_eu\\\\§c0")
  return out
end

local function entry(name, proxy)
  return { type = "gt_machine", methods = {
      getName = "function():string; Returns the machine's name",
      getSensorInformation = "function():table; Returns sensor information about this block",
      getEUStored = "function():number; Returns the EU stored in this block",
      getEUMaxStored = "function():number; Returns the EU capacity of this block",
      setWorkAllowed = "function(work:boolean); Sets whether this block is currently allowed to work",
    }, proxy = proxy, name = name }
end

function LSC.new(state)
  local l = { state = state, calls = {} }
  local function count(n) l.calls[n] = (l.calls[n] or 0) + 1 end
  l.entry = entry("multimachine.supercapacitor", {
    getName = function() count("getName"); return "multimachine.supercapacitor" end,
    getSensorInformation = function()
      count("getSensorInformation")
      if l.state.broken then error(l.state.broken) end
      return lines(l.state)
    end,
    getEUStored = function() count("getEUStored"); return l.state.stored end,
    getEUMaxStored = function() count("getEUMaxStored"); return l.state.capacity end,
    setWorkAllowed = function() count("setWorkAllowed"); error("LUMEN must never call setWorkAllowed") end,
  })
  return l
end

function LSC.machine(name)
  return entry(name, {
    getName = function() return name end,
    getSensorInformation = function() error("not an LSC: don't read me") end,
  })
end

return LSC
