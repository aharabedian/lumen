--[[ lumen.discover: what a computer's components offer, and what their read-only methods return, to build
  LUMEN against the game's real API instead of guesses.

  discover.report(component, opts) -> lines[], summary[]
    component: OpenOS `component`. opts.filter: only types containing this text; opts.all: also the basics
    every computer has (gpu, screen, filesystem...). lines: each component's methods with their docs.
  discover.read(component, ctype) -> lines[]
    Calls every read-only method of every `ctype` component and writes what it returns. Read-only means
    named get..., is... or has... AND documented as taking no arguments ("function():..."); nothing else
    is ever called, so it can't change anything. Tables (like getSensorInformation) get a line per entry.
  discover.probe(component, computer, opts) -> lines[]
    What reactor control needs, for each IC2 reactor and transposer: the reactor's methods with docs,
    producesEnergy / getOfferedEnergy, getSlotInfo(x, y) for x 0..9, y 0..6; each transposer side's
    inventory (name, size) and its stacks (getStackInSlot, every field of the first of each kind) and
    getAllStacks, timed with computer.uptime. Reads only, unless opts.pause: on a reactor that's producing,
    setActive(false) for opts.seconds (default 5), a reading every second (heat, output, producing, total
    damage of the parts a transposer sees in it), then put back: setActive(false) leaves redstone in charge;
    setActive(true) again only if the reactor is then off (it ran on setActive alone).
    opts.sleep(seconds) waits (os.sleep).
  discover.isReactorInventory(name) -> bool   a transposer's inventory name for a reactor ("blockGenerator")
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

---------------------------------------------------------------- probe
local SIDES = { [0] = "bottom", "top", "north", "south", "west", "east" }

-- A table on one line: key=value, sorted by key.
local function inline(t)
  local keys, parts = {}, {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local v = t[k]
    parts[#parts + 1] = tostring(k) .. "=" .. (type(v) == "table" and "{...}" or show(v))
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

-- pcall, keeping every result: ok -> true, results...; failed -> nil, message.
local function try(f, ...)
  local r = table.pack(pcall(f, ...))
  if not r[1] then return nil, tostring(r[2]) end
  return true, table.unpack(r, 2, r.n)
end
local function value(f, ...)
  local ok, v = try(f, ...)
  if ok then return v end
end

-- A reactor's inventory, as a transposer names it: "blockGenerator" (seen in game), or a chamber.
function discover.isReactorInventory(name)
  return type(name) == "string" and (name == "blockGenerator" or name:lower():find("reactor", 1, true) ~= nil)
end

local function reactorSide(t)
  for side = 0, 5 do
    if discover.isReactorInventory(value(t.getInventoryName, side)) then return side end
  end
end

-- Total damage (heat, for vents and exchangers) of the parts a transposer sees in the reactor.
local function partsDamage(t, side)
  local total = 0
  for slot = 1, value(t.getInventorySize, side) or 0 do
    local st = value(t.getStackInSlot, side, slot)
    if type(st) == "table" and type(st.damage) == "number" then total = total + st.damage end
  end
  return total
end

local function probeReactor(lines, component, addr, proxy)
  lines[#lines + 1] = ("== reactor %s (%s)"):format(addr, component.type(addr))
  for _, name in ipairs(methodNames(component, addr)) do
    lines[#lines + 1] = ("  %s  %s"):format(name, docOf(component, addr, name))
  end
  for _, name in ipairs({ "producesEnergy", "getOfferedEnergy", "getHeat", "getMaxHeat", "getReactorEUOutput" }) do
    if proxy[name] then
      local ok, v = try(proxy[name])
      lines[#lines + 1] = ("  %s() -> %s"):format(name, ok and show(v) or ("error: " .. v))
    end
  end
  if not proxy.getSlotInfo then return end
  -- getSlotInfo(x:int, y:int): a reactor is up to 9 columns by 6 rows; which base (0 or 1) is unknown.
  local answered, errors, firstErr = 0, 0, nil
  for y = 0, 6 do
    for x = 0, 9 do
      local ok, v = try(proxy.getSlotInfo, x, y)
      if not ok then
        errors = errors + 1
        firstErr = firstErr or ("getSlotInfo(" .. x .. ", " .. y .. "): " .. v)
      elseif v ~= nil then
        answered = answered + 1
        if answered <= 6 then
          lines[#lines + 1] = ("  getSlotInfo(%d, %d) -> %s"):format(x, y, type(v) == "table" and inline(v) or show(v))
        end
      end
    end
  end
  lines[#lines + 1] = ("  getSlotInfo(0..9, 0..6): %d answered (first 6 shown), %d errors%s"):format(answered, errors,
    firstErr and (" (first: " .. firstErr .. ")") or "")
end

local function probeTransposer(lines, computer, addr, t)
  lines[#lines + 1] = ("== transposer %s"):format(addr)
  for side = 0, 5 do
    local ok, name = try(t.getInventoryName, side)
    local size = ok and name and value(t.getInventorySize, side)
    if not ok or not name then
      lines[#lines + 1] = ("  side %d (%s): %s"):format(side, SIDES[side], ok and "no inventory" or ("error: " .. name))
    else
      lines[#lines + 1] = ("  side %d (%s): %s, %s slots"):format(side, SIDES[side], show(name), tostring(size))
      local n = math.min(tonumber(size) or 0, 120)
      local seen, filled, start = {}, 0, computer.uptime()
      for slot = 1, n do
        local sok, st = try(t.getStackInSlot, side, slot)
        if not sok then
          lines[#lines + 1] = ("    [%d] error: %s"):format(slot, st)
        elseif type(st) == "table" then
          filled = filled + 1
          local kind = tostring(st.name) .. ":" .. tostring(st.label)
          if not seen[kind] then
            seen[kind] = true
            lines[#lines + 1] = ("    [%d] %s"):format(slot, inline(st))
          else
            lines[#lines + 1] = ("    [%d] %s, damage %s/%s"):format(slot, tostring(st.label), tostring(st.damage), tostring(st.maxDamage))
          end
        end
      end
      lines[#lines + 1] = ("    %d filled; %d getStackInSlot calls took %.2f s"):format(filled, n, computer.uptime() - start)
      if t.getAllStacks then
        start = computer.uptime()
        local aok, it = try(t.getAllStacks, side)
        local count, kind = nil, type(it)
        if aok and type(it) == "table" and it.getAll then
          local gok, all = try(it.getAll)
          if gok and type(all) == "table" then count = 0; for _ in pairs(all) do count = count + 1 end end
        elseif aok and it ~= nil then
          count = 0
          for _ = 1, n + 1 do if it() == nil then break end; count = count + 1 end
        end
        lines[#lines + 1] = ("    getAllStacks: %s, %s entries, %.2f s"):format(aok and kind or ("error: " .. tostring(it)),
          tostring(count), computer.uptime() - start)
      end
    end
  end
end

-- Pauses a producing reactor with setActive(false) for opts.seconds, reading every second, then puts it back.
-- setActive is a second "on" input beside redstone (seen in game: the reactor runs if either is on), so
-- putting back is setActive(false) - redstone in charge - and setActive(true) only if that leaves it off,
-- meaning it ran on setActive alone. A pause can't stop a reactor that redstone runs.
local function pauseTest(lines, computer, proxy, transposers, opts)
  local seconds = opts.seconds or 5
  if not proxy.setActive then lines[#lines + 1] = "  pause test: no setActive"; return end
  if value(proxy.producesEnergy) ~= true then
    lines[#lines + 1] = "  pause test skipped: the reactor isn't producing (start it, then run --pause again)"
    return
  end
  local parts
  for _, t in ipairs(transposers) do
    local side = reactorSide(t)
    if side then parts = function() return partsDamage(t, side) end; break end
  end
  local function sample(what)
    lines[#lines + 1] = ("  %-9s t=%.2f heat=%s output=%s producing=%s parts damage=%s"):format(what,
      computer.uptime(), show(value(proxy.getHeat)), show(value(proxy.getReactorEUOutput)),
      show(value(proxy.producesEnergy)), parts and tostring(parts()) or "(no transposer on the reactor)")
  end
  local function set(on)
    local r = table.pack(try(proxy.setActive, on))
    lines[#lines + 1] = ("  setActive(%s) -> %s"):format(tostring(on),
      not r[1] and ("error: " .. tostring(r[2])) or (r.n > 1 and show(r[2]) or "nothing"))
    return r[1]
  end
  lines[#lines + 1] = ("  pause test: setActive(false) for %d s, then put back"):format(seconds)
  sample("before")
  local ok, err = pcall(function()
    if not set(false) then error("setActive(false) failed", 0) end
    for i = 1, seconds do
      opts.sleep(1)
      sample("paused " .. i)
      if i == 1 and value(proxy.producesEnergy) then
        lines[#lines + 1] = "  still producing: its redstone runs it, and setActive can't stop that"
        break
      end
    end
  end)
  if not ok then lines[#lines + 1] = "  pause test failed: " .. tostring(err) end
  local pok = pcall(opts.sleep, 1)
  if pok and value(proxy.producesEnergy) ~= true then
    lines[#lines + 1] = "  off with setActive(false): it ran on setActive alone, so it's started again"
    if not set(true) then lines[#lines + 1] = "  setActive(true) failed - CHECK THE REACTOR" end
    pcall(opts.sleep, 1)
  else
    lines[#lines + 1] = "  put back: setActive(false), its redstone runs it"
  end
  sample("after")
end

function discover.probe(component, computer, opts)
  opts = opts or {}
  local lines, transposers = {}, {}
  local tlist = sortedComponents(component, "transposer")
  for _, c in ipairs(tlist) do transposers[#transposers + 1] = component.proxy(c.addr) end
  local reactors = {}
  for _, ctype in ipairs({ "reactor", "reactor_chamber" }) do
    for _, c in ipairs(sortedComponents(component, ctype)) do reactors[#reactors + 1] = c end
  end
  if #reactors == 0 then lines[#lines + 1] = "no reactor component found (an adapter next to the reactor or a chamber)" end
  for _, c in ipairs(reactors) do
    local proxy = component.proxy(c.addr)
    probeReactor(lines, component, c.addr, proxy)
    if opts.pause then pauseTest(lines, computer, proxy, transposers, opts) end
    lines[#lines + 1] = ""
  end
  if #tlist == 0 then lines[#lines + 1] = "no transposer found" end
  for i, c in ipairs(tlist) do
    probeTransposer(lines, computer, c.addr, transposers[i])
    lines[#lines + 1] = ""
  end
  return lines
end

return discover
