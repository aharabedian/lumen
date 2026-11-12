--[[ lumen.sources: the power sources a computer reads. GT generators (any gt_machine named in cfg.sources: an
  LFTR, turbines, combustion engines...) and IC2 nuclear reactors (found by themselves, and named in cfg.sources
  if you like). Only reads: nothing here changes the game.

  sources.REACTORS                   component types read as IC2 reactors ("reactor", "reactor_chamber")
  sources.new(component, cfg) -> s   cfg: lumen.config output (sources = { { address, name, alwaysOn }... })
  s:read() -> list                   cfg.sources in order, then reactors not named there (by address). Each:
    { name, address (the component's, or the configured start when not found), kind = "gt" | "reactor",
      alwaysOn, ok = true,
      active      bool: GT isMachineActive(); a reactor producesEnergy(), else EU/t above 0
      output      EU/t: a reactor's getReactorEUOutput(); a GT generator's from its sensor lines (a line with
                  "EU/t" saying output / generates / produces), nil when none says
      progress    0..1 (GT, while it has a recipe) | nil
      heat        0..1: getHeat() / getMaxHeat() (reactors) | nil
      problems    number (GT: maintenance problems, from its sensor lines) | nil when they don't say }
    or { name, address, kind, alwaysOn, ok = false, err } (not found, unloaded chunk, broken...)
  sources.gtLines(lines) -> { output?, problems? }   what LUMEN understands of a GT machine's sensor lines

  Which methods GT generators and IC2 reactors answer, and with what, is checked in game with lumen-discover
  --read (docs/architecture.md says what's confirmed).
]]

local sources = {}

sources.REACTORS = { reactor = true, reactor_chamber = true }

local S = {}
S.__index = S

function sources.new(component, cfg)
  return setmetatable({ component = component, cfg = cfg }, S)
end

local function call(proxy, name)
  if type(proxy[name]) ~= "function" then return nil end
  local ok, v = pcall(proxy[name])
  if ok then return v end
end

-- The number after a word, in text with § codes and thousands commas taken out.
local function numberIn(s)
  local n = s:gsub(",", ""):match("(%-?%d+%.?%d*)")
  return n and tonumber(n)
end

function sources.gtLines(lines)
  local out = {}
  for _, raw in ipairs(lines or {}) do
    local line = tostring(raw):gsub("\194\167.", ""):gsub("\\+", " ")
    local low = line:lower()
    if out.problems == nil and low:find("maintenance_status%.") then
      out.problems = low:find("maintenance_status%.ok") and 0 or 1
    elseif out.problems == nil and low:find("problems") then
      out.problems = numberIn(low:match("problems(.*)$") or "")
    end
    if out.output == nil and low:find("eu/t", 1, true)
      and (low:find("output") or low:find("generat") or low:find("produc")) then
      out.output = numberIn(line)
    end
  end
  return out
end

-- The component whose address starts with `prefix`, of a type LUMEN reads as a source.
function S:find(prefix)
  for address, ctype in self.component.list() do
    if address:sub(1, #prefix) == prefix and (ctype == "gt_machine" or sources.REACTORS[ctype]) then
      return address, ctype
    end
  end
end

local function readReactor(r, proxy)
  local heat, maxHeat = call(proxy, "getHeat"), call(proxy, "getMaxHeat")
  if heat == nil and maxHeat == nil then
    r.ok, r.err = false, "no answer (unloaded chunk?)"
    return r
  end
  r.ok = true
  r.heat = (heat and maxHeat and maxHeat > 0) and heat / maxHeat or nil
  r.output = call(proxy, "getReactorEUOutput") or call(proxy, "getReactorEnergyOutput")
  local produces = call(proxy, "producesEnergy")
  if produces ~= nil then r.active = produces and true or false else r.active = (r.output or 0) > 0 end
  return r
end

local function readGt(r, proxy)
  local ok, lines = pcall(proxy.getSensorInformation)
  if not ok or type(lines) ~= "table" then
    r.ok, r.err = false, ok and "no sensor information" or (tostring(lines):gsub("^[^:]*:%d+: ", ""))
    return r
  end
  r.ok = true
  local info = sources.gtLines(lines)
  r.output, r.problems = info.output, info.problems
  r.active = call(proxy, "isMachineActive") and true or false
  local done, max = call(proxy, "getWorkProgress"), call(proxy, "getWorkMaxProgress")
  if r.active and done and max and max > 0 then r.progress = math.min(1, done / max) end
  return r
end

function S:readOne(address, ctype, name, alwaysOn)
  local r = { name = name, address = address, kind = sources.REACTORS[ctype] and "reactor" or "gt", alwaysOn = alwaysOn }
  local proxy = self.component.proxy(address)
  if not proxy then r.ok, r.err = false, "not connected"; return r end
  if r.kind == "reactor" then return readReactor(r, proxy) end
  return readGt(r, proxy)
end

function S:read()
  local out, named = {}, {}
  for _, s in ipairs(self.cfg.sources or {}) do
    local address, ctype = self:find(s.address)
    if address then
      named[address] = true
      out[#out + 1] = self:readOne(address, ctype, s.name, s.alwaysOn)
    else
      out[#out + 1] = { name = s.name, address = s.address, kind = "gt", alwaysOn = s.alwaysOn, ok = false,
        err = "nothing found at " .. s.address }
    end
  end
  local found = {}
  for address, ctype in self.component.list() do
    if sources.REACTORS[ctype] and not named[address] then found[#found + 1] = { address, ctype } end
  end
  table.sort(found, function(a, b) return a[1] < b[1] end)
  for _, f in ipairs(found) do out[#out + 1] = self:readOne(f[1], f[2], "Reactor " .. f[1]:sub(1, 4), false) end
  return out
end

return sources
