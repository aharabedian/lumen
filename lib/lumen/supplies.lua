--[[ lumen.supplies: counting what generators burn and make (fuel rods, coolant, benzene, spent rods...) in an AE2
  ME system, through an adapter on an ME interface or controller ("me_interface" | "me_controller"). Only reads:
  one lookup each, getItemInNetwork(name, damage) or getFluidInNetwork(name), a tick each.

  supplies.new(component, cfg) -> s       cfg.supplies: { { name, item, damage | fluid, below, above, hours, feeds }... }
  s:read() -> { { name, kind = "item" | "fluid", amount (items, or L of a fluid; 0 when there's none), label,
                  ok, err, cfg }... }       in cfg.supplies order
  supplies.find(component) -> address | nil   the ME component used (an interface first)
  supplies.search(component, text) -> list | nil, err   for lumen-setup: items whose label is `text` (AE2 matches it
                                       exactly, so a big network never comes to the computer), and fluids whose
                                       label or name has it in (any case). { { kind, name, damage, label, amount }... }
  supplies.unit(kind) -> "" | " L"
  supplies.status(r) -> level ("bad" | "warn" | nil), text   a reading with rate (per hour) and lasts (seconds):
                                       "none left", "low", "piling up", "lasts 8h57m", "can't be counted"; when fine,
                                       "lasts 3d 6h", "+4.00/h" or "steady"
]]

local power = require("lumen.power")

local supplies = {}

function supplies.status(r)
  local c = r.cfg or {}
  if not r.ok then return "warn", "can't be counted" end
  if c.below and r.amount <= 0 then return "bad", "none left" end
  if c.below and r.amount < c.below then return "warn", "low" end
  if c.above and r.amount > c.above then return "warn", "piling up" end
  local lasts = r.lasts and ("lasts " .. power.duration(r.lasts)) or nil
  if c.hours and r.lasts and r.lasts < c.hours * 3600 then return "warn", lasts end
  if lasts then return nil, lasts end
  if r.rate and r.rate > 0.5 then return nil, "+" .. power.si(r.rate) .. "/h" end
  return nil, "steady"
end

local TYPES = { "me_interface", "me_controller" }

function supplies.find(component)
  for _, t in ipairs(TYPES) do
    local address = component.list(t, true)()
    if address then return address end
  end
end

function supplies.unit(kind) return kind == "fluid" and " L" or "" end

local S = {}
S.__index = S

function supplies.new(component, cfg) return setmetatable({ component = component, cfg = cfg }, S) end

local function reason(err) return (tostring(err):gsub("^[^:]*:%d+: ", "")) end

function S:read()
  local out = {}
  local list = self.cfg.supplies or {}
  if #list == 0 then return out end
  local address = supplies.find(self.component)
  local proxy = address and self.component.proxy(address)
  for _, c in ipairs(list) do
    local r = { name = c.name, kind = c.fluid and "fluid" or "item", cfg = c, ok = false }
    if not proxy then
      r.err = "no ME interface or controller (an adapter on one)"
    else
      local ok, v = pcall(function()
        if c.fluid then return proxy.getFluidInNetwork(c.fluid) end
        return proxy.getItemInNetwork(c.item, c.damage or 0)
      end)
      if not ok then r.err = reason(v)
      else
        r.ok = true
        r.amount = type(v) == "table" and (tonumber(c.fluid and v.amount or v.size) or 0) or 0
        r.label = type(v) == "table" and v.label or nil
      end
    end
    out[#out + 1] = r
  end
  return out
end

function supplies.search(component, text)
  local address = supplies.find(component)
  local proxy = address and component.proxy(address)
  if not proxy then return nil, "no ME interface or controller found (put an adapter on one)" end
  local out = {}
  local ok, items = pcall(function() return proxy.getItemsInNetwork({ label = text }) end)
  if not ok then return nil, reason(items) end
  for _, it in ipairs(items or {}) do
    out[#out + 1] = { kind = "item", name = it.name, damage = it.damage or 0, label = it.label or it.name, amount = it.size or 0 }
  end
  local okF, fluids = pcall(function() return proxy.getFluidsInNetwork() end)
  if okF then
    local want = text:lower()
    for _, fl in ipairs(fluids or {}) do
      local label = tostring(fl.label or fl.name)
      if label:lower():find(want, 1, true) or tostring(fl.name):lower():find(want, 1, true) then
        out[#out + 1] = { kind = "fluid", name = fl.name, label = label, amount = fl.amount or 0 }
      end
    end
  end
  return out
end

return supplies
