--[[ lumen.setup.scan: what lumen-setup's screen offers, read from the attached components. Only reads.

  scan.snapshot(component) -> snap
    snap = { lscs = { { address, ok, fill }... },        lumen.power readings (fill 0..1)
             reactors = { address... },                  IC2 reactors (sources.REACTORS)
             gts = { { address, name }... },             GT machines that aren't LSCs, name = getName()
             redstone = { address... },                  Redstone I/O blocks and cards
             modem = bool,                               a network card, for LENS
             presence = { "radar" } | {},                a Computronics radar, to wake big mode
             me = bool }                                 an ME interface or controller, for supplies
    every list sorted by address
  scan.inputs(component, address) -> { { side = "south", level = 15 }... } | nil, err
    the redstone signals coming into a block now (sides with none left out): 6 calls, one a tick
]]

local power   = require("lumen.power")
local sources = require("lumen.sources")
local presence = require("lumen.presence")
local supplies = require("lumen.supplies")

local scan = {}

scan.SIDES = { "bottom", "top", "north", "south", "west", "east" }   -- OpenComputers' side numbers 0-5

function scan.snapshot(component)
  local snap = { lscs = {}, reactors = {}, gts = {}, redstone = {}, modem = component.isAvailable("modem") and true or false,
    presence = presence.scan(component), me = supplies.find(component) ~= nil }
  for _, r in ipairs(power.new(component, { names = {} }):read()) do
    snap.lscs[#snap.lscs + 1] = { address = r.address, ok = r.ok, fill = r.fill }
  end
  local found = {}
  for address, ctype in component.list() do found[#found + 1] = { address, ctype } end
  table.sort(found, function(a, b) return a[1] < b[1] end)
  for _, f in ipairs(found) do
    local address, ctype = f[1], f[2]
    if sources.REACTORS[ctype] then
      snap.reactors[#snap.reactors + 1] = address
    elseif ctype == "redstone" then
      snap.redstone[#snap.redstone + 1] = address
    elseif ctype == "gt_machine" then
      local proxy = component.proxy(address)
      local ok, name = pcall(proxy and proxy.getName or error)
      if not ok or name ~= power.LSC then
        snap.gts[#snap.gts + 1] = { address = address, name = ok and tostring(name) or "?" }
      end
    end
  end
  table.sort(snap.lscs, function(a, b) return a.address < b.address end)
  return snap
end

function scan.inputs(component, address)
  local proxy = component.proxy(address)
  if not proxy then return nil, "not found" end
  local out = {}
  for n, side in ipairs(scan.SIDES) do
    local ok, v = pcall(proxy.getInput, n - 1)
    if not ok then return nil, tostring(v) end
    if type(v) == "number" and v > 0 then out[#out + 1] = { side = side, level = v } end
  end
  return out
end

return scan
