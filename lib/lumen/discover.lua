--[[ lumen.discover: what a computer's components offer, and what their read-only methods return, to build
  LUMEN against the game's real API instead of guesses.

  discover.report(component, opts) -> lines[], summary[]
    component: OpenOS `component`. opts.filter: only types containing this text; opts.all: also the basics
    every computer has (gpu, screen, filesystem...). lines: each component's methods with their docs.
  discover.read(component, ctype) -> lines[]
    Calls every read-only method of every `ctype` component and writes what it returns. Read-only means
    named get..., is... or has... AND documented as taking no arguments ("function():..."); nothing else
    is ever called, so it can't change anything. Tables (like getSensorInformation) get a line per entry.
]]

local discover = {}

discover.BASICS = {
  computer = true, eeprom = true, filesystem = true, gpu = true, internet = true, keyboard = true,
  modem = true, screen = true,
}

local function sortedComponents(component, ctype)
  local found = {}
  for addr, t in component.list(ctype, ctype ~= nil) do found[#found + 1] = { addr = addr, type = t } end
  table.sort(found, function(a, b)
    if a.type ~= b.type then return a.type < b.type end
    return a.addr < b.addr
  end)
  return found
end

local function methodNames(component, addr)
  local names = {}
  for name in pairs(component.methods(addr) or {}) do names[#names + 1] = name end
  table.sort(names)
  return names
end

local function docOf(component, addr, name)
  local ok, doc = pcall(component.doc, addr, name)
  return ok and type(doc) == "string" and doc or ""
end

function discover.report(component, opts)
  opts = opts or {}
  local lines, summary = {}, {}
  for _, c in ipairs(sortedComponents(component)) do
    local wanted = opts.filter and c.type:find(opts.filter, 1, true)
    local detailed = wanted or (not opts.filter and (opts.all or not discover.BASICS[c.type]))
    local names = detailed and methodNames(component, c.addr) or {}
    summary[#summary + 1] = ("%-24s %s%s"):format(c.type, c.addr, detailed and (" (" .. #names .. " methods)") or "")
    if detailed then
      lines[#lines + 1] = ("== %s %s"):format(c.type, c.addr)
      for _, name in ipairs(names) do lines[#lines + 1] = ("  %s  %s"):format(name, docOf(component, c.addr, name)) end
      lines[#lines + 1] = ""
    end
  end
  return lines, summary
end

-- A returned value as text: numbers exactly (integer or float), strings quoted.
local function show(v)
  local t = type(v)
  if t == "string" then return ("%q"):format(v) end
  if t == "number" then
    if math.type(v) == "integer" then return tostring(v) .. " (integer)" end
    return ("%.17g (float)"):format(v)
  end
  return tostring(v)
end

local function readOnly(name, doc)
  return (name:find("^get") or name:find("^is") or name:find("^has")) and doc:find("^%s*function%(%)") ~= nil
end

function discover.read(component, ctype)
  local lines = {}
  local found = sortedComponents(component, ctype)
  if #found == 0 then return { ("no %s component found"):format(ctype) } end
  for _, c in ipairs(found) do
    lines[#lines + 1] = ("== %s %s"):format(c.type, c.addr)
    local proxy = component.proxy(c.addr)
    local skipped = {}
    for _, name in ipairs(methodNames(component, c.addr)) do
      if readOnly(name, docOf(component, c.addr, name)) then
        local results = table.pack(pcall(proxy[name]))
        if not results[1] then
          lines[#lines + 1] = ("  %s -> error: %s"):format(name, tostring(results[2]))
        elseif type(results[2]) == "table" then
          lines[#lines + 1] = ("  %s -> table"):format(name)
          local keys = {}
          for k in pairs(results[2]) do keys[#keys + 1] = k end
          table.sort(keys, function(a, b)
            if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
            return tostring(a) < tostring(b)
          end)
          for _, k in ipairs(keys) do lines[#lines + 1] = ("    [%s] %s"):format(tostring(k), show(results[2][k])) end
        else
          local vals = {}
          for i = 2, results.n do vals[#vals + 1] = show(results[i]) end
          lines[#lines + 1] = ("  %s -> %s"):format(name, #vals > 0 and table.concat(vals, ", ") or "nothing")
        end
      else
        skipped[#skipped + 1] = name
      end
    end
    if #skipped > 0 then lines[#lines + 1] = "  not called (may change something, or take arguments): " .. table.concat(skipped, ", ") end
    lines[#lines + 1] = ""
  end
  return lines
end

return discover
