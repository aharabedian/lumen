--[[ lumen.setup.editor: lumen.cfg as lumen-setup's screen edits it. Pure: it takes the config as loaded and a
  lumen.setup.scan snapshot, and never touches components or files.

  Editor.new(old, snap) -> ed     old: lumen.cfg as a plain table (never changed). Reactors found that aren't in
                                  old.sources are added ("Reactor eeee"), as the text setup does
  ed.c                            the config being edited
  ed.snap, ed.rescan(snap)        the snapshot in use; rescan keeps every edit
  ed.short(address) -> first 8 characters (what lumen.cfg keeps)

  LSCs     ed.lscRows() -> { key, address, found = scan entry | nil, name | nil }[]   found ones, then named
           ones not found.  ed.nameLsc(key, name) ("" removes it; switches following it follow a new name)
           ed.dropLsc(key)
  Sources  ed.sourceRows() -> { key, kind = "reactor" | "gt", label, found?, entry? }[]   reactors, GT machines,
           then configured ones not found.  ed.showSource(key, on) -> true | nil, why
           ed.setSource(key, field, value) -> true | nil, why   field: "name" (unique; switches follow it) |
           "alwaysOn".  ed.dropSource(key)
  Switches ed.c.control (in order).  ed.addSwitch() -> i | nil, why    ed.copySwitch(i) -> i | nil, why
           (the next name, "MOX 1" -> "MOX 2", and the next redstone block or GT machine no switch uses; the
           rest copied but its source)   ed.deleteSwitch(i)
           ed.setSwitch(i, field, value) -> true | nil, why   field: name, kind ("redstone" | "machine"),
           redstone, machine, side, invert, onBelow, offAbove, lsc (nil = all), source (nil = none)
           ed.setFault(i, field, value) -> true | nil, why    field: "on" (true adds one, false removes it),
           redstone, side, invert, latch, stop
           ed.choices(what, i) -> { value, label, note }[]    what: "redstone" | "faultRedstone" | "machine" |
           "lsc" | "source": what a switch's field may be, with who uses each
           ed.sideName(side) -> "north" (names, aliases or 0-5)
  General  ed.set(key, value)
  Saving   ed.result() -> a copy of the config to save
           ed.check() -> true | nil, why        lumen.config's checks on the result
           ed.changes() -> lines[]              "+ switch MOX 2: ...", "~ lowFill: 25 -> 20", "- source ..."
           ed.warnings() -> lines[]             components not found, two switches on one output, a fault read
                                                on a side a switch drives, a switch's source or LSC missing
]]

local config = require("lumen.config")
local render = require("lumen.setup.render")

local Editor = {}

local SIDES = { "bottom", "top", "north", "south", "west", "east" }
local ALIAS = { down = "bottom", up = "top", back = "north", front = "south", right = "west", left = "east" }
local GENERAL = { "interval", "lowFill", "criticalFill", "drainWarnHours", "drainBadHours", "drainAverage", "inputDrop",
  "maxPassiveLoss", "heatWarn", "heatBad", "beep", "lensPort", "lensNode", "lensToken" }

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
local function short(a) return tostring(a or "?"):sub(1, 8) end
local function sameAddr(full, prefix)
  return type(full) == "string" and type(prefix) == "string" and prefix ~= "" and full:sub(1, #prefix) == prefix
end
local function named(v) return type(v) == "string" and v ~= "" end

function Editor.sideName(side)
  if math.type(side) == "integer" then return SIDES[side + 1] or tostring(side) end
  return ALIAS[side] or side
end

-- "MOX 1" -> "MOX 2"; "Vac nuke" -> "Vac nuke 2"; the first not in `taken`.
local function nextName(name, taken)
  local base, n = name:match("^(.-)%s*(%d+)$")
  if not base or base == "" then base, n = name, 1 end
  n = tonumber(n)
  repeat n = n + 1 until not taken[base .. " " .. n]
  return base .. " " .. n
end

function Editor.new(old, snap)
  local ed = { snap = snap, short = short, sideName = Editor.sideName }
  local c = copy(old)
  c.names = c.names or {}
  c.sources = c.sources or {}
  c.control = c.control or {}
  ed.c = c

  local function sourceFor(address)
    for _, s in ipairs(c.sources) do if sameAddr(address, s.address) then return s end end
  end
  local function sourceNamed(name)
    for _, s in ipairs(c.sources) do if s.name == name then return s end end
  end
  local function uniqueSourceName(base)
    if not sourceNamed(base) then return base end
    local taken = {}
    for _, s in ipairs(c.sources) do taken[s.name] = true end
    return nextName(base, taken)
  end
  for _, a in ipairs(snap.reactors or {}) do
    if not sourceFor(a) then
      c.sources[#c.sources + 1] = { address = short(a), name = uniqueSourceName("Reactor " .. a:sub(1, 4)) }
    end
  end

  function ed.rescan(s) ed.snap = s end

  ---------------------------------------------------------------- LSCs
  local function lscName(address)
    for prefix, name in pairs(c.names) do
      if sameAddr(address, prefix) then return name, prefix end
    end
  end

  function ed.lscRows()
    local out, used = {}, {}
    for _, l in ipairs(ed.snap.lscs or {}) do
      local name, prefix = lscName(l.address)
      if prefix then used[prefix] = true end
      out[#out + 1] = { key = prefix or short(l.address), address = l.address, found = l, name = name }
    end
    local rest = {}
    for prefix in pairs(c.names) do if not used[prefix] then rest[#rest + 1] = prefix end end
    table.sort(rest)
    for _, prefix in ipairs(rest) do out[#out + 1] = { key = prefix, address = prefix, name = c.names[prefix] } end
    return out
  end

  function ed.nameLsc(key, name)
    local was = c.names[key]
    c.names[key] = named(name) and name or nil
    -- Switches following it follow the new name; with none, they keep the old one (and a warning says so).
    if was and c.names[key] then
      for _, sw in ipairs(c.control) do if sw.lsc == was then sw.lsc = c.names[key] end end
    end
  end
  function ed.dropLsc(key) ed.nameLsc(key, nil) end

  ---------------------------------------------------------------- sources
  function ed.sourceRows()
    local out, used = {}, {}
    local function add(address, kind, label)
      local e = sourceFor(address)
      if e then used[e] = true end
      out[#out + 1] = { key = e and e.address or short(address), address = address, kind = kind, label = label,
        found = true, entry = e }
    end
    for _, a in ipairs(ed.snap.reactors or {}) do add(a, "reactor", "IC2 reactor") end
    for _, g in ipairs(ed.snap.gts or {}) do add(g.address, "gt", g.name) end
    for _, s in ipairs(c.sources) do
      if not used[s] then out[#out + 1] = { key = s.address, address = s.address, kind = "?", label = "not found", entry = s } end
    end
    return out
  end
  local function sourceRow(key)
    for _, r in ipairs(ed.sourceRows()) do if r.key == key then return r end end
  end

  local function renameRefs(field, was, now)
    for _, sw in ipairs(c.control) do if sw[field] == was then sw[field] = now end end
  end

  function ed.showSource(key, on)
    local r = sourceRow(key)
    if not r then return nil, "nothing selected" end
    if on and not r.entry then
      local label = r.label:gsub("^.*%.", "")
      c.sources[#c.sources + 1] = { address = r.key, name = uniqueSourceName(label ~= "" and label or ("Source " .. r.key)) }
    elseif not on and r.entry then
      if r.kind == "reactor" then return nil, "IC2 reactors are always shown; give it a name instead" end
      ed.dropSource(key)
    end
    return true
  end

  function ed.setSource(key, field, value)
    local r = sourceRow(key)
    if not (r and r.entry) then return nil, "it isn't shown" end
    if field == "name" then
      if not named(value) then return nil, "a source needs a name" end
      local other = sourceNamed(value)
      if other and other ~= r.entry then return nil, "another source is already called " .. value end
      renameRefs("source", r.entry.name, value)
      r.entry.name = value
    elseif field == "alwaysOn" then
      r.entry.alwaysOn = value and true or nil
    end
    return true
  end

  function ed.dropSource(key)
    for i, s in ipairs(c.sources) do
      if s.address == key then
        renameRefs("source", s.name, nil)
        table.remove(c.sources, i)
        return
      end
    end
  end

  ---------------------------------------------------------------- switches
  local function switchNamed(name)
    for _, sw in ipairs(c.control) do if sw.name == name then return sw end end
  end
  local function takenNames()
    local t = {}
    for _, sw in ipairs(c.control) do t[sw.name] = true end
    return t
  end
  -- The first redstone block (or GT machine) found that no switch drives, else the first one found.
  local function freeRedstone(except)
    for _, a in ipairs(ed.snap.redstone or {}) do
      local used = false
      for _, sw in ipairs(c.control) do if sw ~= except and sameAddr(a, sw.redstone) then used = true end end
      if not used then return short(a) end
    end
    return ed.snap.redstone and ed.snap.redstone[1] and short(ed.snap.redstone[1])
  end
  local function freeMachine(except)
    for _, g in ipairs(ed.snap.gts or {}) do
      local used = false
      for _, sw in ipairs(c.control) do if sw ~= except and sameAddr(g.address, sw.machine) then used = true end end
      if not used then return short(g.address) end
    end
    return ed.snap.gts and ed.snap.gts[1] and short(ed.snap.gts[1].address)
  end

  function ed.addSwitch()
    local sw = { onBelow = 30, offAbove = 90 }
    local taken = takenNames()
    sw.name = taken["Switch 1"] and nextName("Switch 1", taken) or "Switch 1"
    sw.redstone = freeRedstone()
    if sw.redstone then sw.side = "north"
    else
      sw.machine = freeMachine()
      if not sw.machine then return nil, "no Redstone I/O block, redstone card or GT machine found to switch with" end
    end
    c.control[#c.control + 1] = sw
    return #c.control
  end

  function ed.copySwitch(i)
    local src = c.control[i]
    if not src then return nil, "nothing selected" end
    local sw = copy(src)
    sw.name = nextName(src.name, takenNames())
    sw.source = nil
    if src.redstone then
      sw.redstone = freeRedstone(nil) or src.redstone
      -- A fault line into the switch's own block moves with it.
      if sw.fault and sw.fault.redstone == src.redstone then sw.fault.redstone = sw.redstone end
    elseif src.machine then
      sw.machine = freeMachine(nil) or src.machine
    end
    table.insert(c.control, i + 1, sw)
    return i + 1
  end

  function ed.deleteSwitch(i) table.remove(c.control, i) end

  local function percent(v)
    return math.type(v) == "integer" and v >= 0 and v <= 100
  end

  function ed.setSwitch(i, field, value)
    local sw = c.control[i]
    if not sw then return nil, "nothing selected" end
    if field == "name" then
      if not named(value) then return nil, "a switch needs a name" end
      local other = switchNamed(value)
      if other and other ~= sw then return nil, "another switch is already called " .. value end
      sw.name = value
    elseif field == "kind" then
      if value == "redstone" and not sw.redstone then
        local r = freeRedstone(sw)
        if not r then return nil, "no Redstone I/O block or redstone card found" end
        sw.machine, sw.redstone, sw.side = nil, r, sw.side or "north"
      elseif value == "machine" and not sw.machine then
        local m = freeMachine(sw)
        if not m then return nil, "no GT machine found besides LSCs" end
        sw.redstone, sw.side, sw.invert, sw.strength, sw.machine = nil, nil, nil, nil, m
      end
    elseif field == "onBelow" then
      if not percent(value) or value >= sw.offAbove then
        return nil, ("on below must be a whole percent under off above (%g%%)"):format(sw.offAbove)
      end
      sw.onBelow = value
    elseif field == "offAbove" then
      if not percent(value) or value <= sw.onBelow then
        return nil, ("off above must be a whole percent over on below (%g%%)"):format(sw.onBelow)
      end
      sw.offAbove = value
    elseif field == "invert" then
      sw.invert = value and true or nil
    elseif field == "side" or field == "redstone" or field == "machine" or field == "lsc" or field == "source" then
      sw[field] = value
    else
      return nil, "unknown field " .. tostring(field)
    end
    return true
  end

  function ed.setFault(i, field, value)
    local sw = c.control[i]
    if not sw then return nil, "nothing selected" end
    if field == "on" then
      if value and not sw.fault then
        local r = sw.redstone or freeRedstone()
        if not r then return nil, "no Redstone I/O block or redstone card found for the fault signal" end
        local side = "south"
        if r == sw.redstone and Editor.sideName(sw.side) == side then side = "north" end
        sw.fault = { redstone = r, side = side, invert = false, latch = false, stop = true }
      elseif not value then
        sw.fault = nil
      end
      return true
    end
    if not sw.fault then return nil, "it has no fault input" end
    if field == "redstone" or field == "side" then sw.fault[field] = value
    elseif field == "invert" or field == "latch" or field == "stop" then sw.fault[field] = value and true or false
    else return nil, "unknown field " .. tostring(field) end
    return true
  end

  -- Who uses a component: "MOX 1 (signal north), MOX 1 (fault south)".
  local function users(address)
    local out = {}
    for _, sw in ipairs(c.control) do
      if sameAddr(address, sw.redstone) then out[#out + 1] = ("%s (signal %s)"):format(sw.name, Editor.sideName(sw.side)) end
      if sameAddr(address, sw.machine) then out[#out + 1] = sw.name end
      if sw.fault and sameAddr(address, sw.fault.redstone) then
        out[#out + 1] = ("%s (fault %s)"):format(sw.name, Editor.sideName(sw.fault.side))
      end
    end
    return #out > 0 and ("used by " .. table.concat(out, ", ")) or "not used"
  end

  function ed.choices(what, i)
    local sw = c.control[i] or {}
    local out = {}
    if what == "redstone" or what == "faultRedstone" then
      local current = what == "redstone" and sw.redstone or (sw.fault and sw.fault.redstone)
      local seen = false
      for _, a in ipairs(ed.snap.redstone or {}) do
        if sameAddr(a, current) then seen = true end
        out[#out + 1] = { value = short(a), label = "redstone " .. short(a), note = users(a) }
      end
      if current and not seen then out[#out + 1] = { value = current, label = "redstone " .. current, note = "not found" } end
    elseif what == "machine" then
      local seen = false
      for _, g in ipairs(ed.snap.gts or {}) do
        if sameAddr(g.address, sw.machine) then seen = true end
        out[#out + 1] = { value = short(g.address), label = ("%s (%s)"):format(g.name, short(g.address)), note = users(g.address) }
      end
      if sw.machine and not seen then out[#out + 1] = { value = sw.machine, label = sw.machine, note = "not found" } end
    elseif what == "lsc" then
      out[1] = { value = nil, label = "all LSCs together", note = "" }
      local seen = {}
      for _, r in ipairs(ed.lscRows()) do
        if r.name and not seen[r.name] then
          seen[r.name] = true
          out[#out + 1] = { value = r.name, label = r.name, note = r.found and "" or "not found" }
        end
      end
    elseif what == "source" then
      out[1] = { value = nil, label = "none", note = "" }
      for _, s in ipairs(c.sources) do
        local by = {}
        for _, o in ipairs(c.control) do if o.source == s.name and o ~= sw then by[#by + 1] = o.name end end
        out[#out + 1] = { value = s.name, label = s.name, note = #by > 0 and ("switched by " .. table.concat(by, ", ")) or "" }
      end
    end
    return out
  end

  function ed.set(k, v) c[k] = v end

  ---------------------------------------------------------------- saving
  function ed.result() return copy(c) end

  function ed.check()
    local ok, why = config.check(copy(c))
    if not ok then return nil, why end
    return true
  end

  local function describeSwitch(sw)
    local s = sw.redstone
      and ("redstone %s %s%s"):format(sw.redstone, tostring(Editor.sideName(sw.side)), sw.invert and " (signal = stop)" or "")
      or ("GT machine %s"):format(tostring(sw.machine))
    s = s .. (", on below %g%%, off above %g%%"):format(sw.onBelow, sw.offAbove)
    if sw.lsc then s = s .. ", follows " .. sw.lsc end
    if sw.source then s = s .. ", source " .. sw.source end
    if sw.fault then
      local f = sw.fault
      s = s .. (", fault from %s %s"):format(f.redstone, tostring(Editor.sideName(f.side)))
      local flags = {}
      if f.invert then flags[#flags + 1] = "OK signal" end
      if f.latch then flags[#flags + 1] = "latch" end
      if f.stop == false then flags[#flags + 1] = "alert only" end
      if #flags > 0 then s = s .. " (" .. table.concat(flags, ", ") .. ")" end
    end
    return s
  end
  ed.describeSwitch = describeSwitch

  local function show(k, v)
    if v == nil then return "none" end
    if k == "lensToken" then return "(secret)" end
    return type(v) == "table" and render.lua(v) or tostring(v)
  end

  function ed.changes()
    local out = {}
    local function def(t, k)
      if t[k] ~= nil then return t[k] end
      return config.DEFAULTS[k]
    end
    for _, k in ipairs(GENERAL) do
      local a, b = def(old, k), def(c, k)
      if a ~= b then out[#out + 1] = ("~ %s: %s -> %s"):format(k, show(k, a), show(k, b)) end
    end
    local oldNames = old.names or {}
    local keys, seen = {}, {}
    for k in pairs(oldNames) do keys[#keys + 1] = k; seen[k] = true end
    for k in pairs(c.names) do if not seen[k] then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local a, b = oldNames[k], c.names[k]
      if a == nil then out[#out + 1] = ("+ LSC %s: %s"):format(k, b)
      elseif b == nil then out[#out + 1] = ("- LSC %s: %s"):format(k, a)
      elseif a ~= b then out[#out + 1] = ("~ LSC %s: %s -> %s"):format(k, a, b) end
    end
    local function src(s) return s.name .. (s.alwaysOn and " (always on)" or "") end
    local before = {}
    for _, s in ipairs(old.sources or {}) do before[s.address] = s end
    local now = {}
    for _, s in ipairs(c.sources) do
      now[s.address] = true
      local was = before[s.address]
      if not was then out[#out + 1] = ("+ source %s: %s"):format(s.address, src(s))
      elseif src(was) ~= src(s) then out[#out + 1] = ("~ source %s: %s -> %s"):format(s.address, src(was), src(s)) end
    end
    for _, s in ipairs(old.sources or {}) do
      if not now[s.address] then out[#out + 1] = ("- source %s: %s"):format(s.address, src(s)) end
    end
    local oldSw = {}
    for _, sw in ipairs(old.control or {}) do oldSw[sw.name] = sw end
    local nowSw = {}
    for _, sw in ipairs(c.control) do
      nowSw[sw.name] = true
      local was = oldSw[sw.name]
      if not was then out[#out + 1] = ("+ switch %s: %s"):format(sw.name, describeSwitch(sw))
      elseif describeSwitch(was) ~= describeSwitch(sw) then out[#out + 1] = ("~ switch %s: %s"):format(sw.name, describeSwitch(sw)) end
    end
    for _, sw in ipairs(old.control or {}) do
      if not nowSw[sw.name] then out[#out + 1] = ("- switch %s"):format(sw.name) end
    end
    return out
  end

  local function foundIn(list, prefix, field)
    for _, x in ipairs(list or {}) do
      if sameAddr(field and x[field] or x, prefix) then return true end
    end
  end

  function ed.warnings()
    local out = {}
    local drives = {}
    for _, sw in ipairs(c.control) do
      if sw.redstone then
        if not foundIn(ed.snap.redstone, sw.redstone) then
          out[#out + 1] = ("switch %s: redstone %s wasn't found - check it's connected, or pick another"):format(sw.name, sw.redstone)
        end
        local at = sw.redstone .. " " .. tostring(Editor.sideName(sw.side))
        if drives[at] then out[#out + 1] = ("switches %s and %s both drive redstone %s"):format(drives[at], sw.name, at) end
        drives[at] = sw.name
      elseif sw.machine and not foundIn(ed.snap.gts, sw.machine, "address") then
        out[#out + 1] = ("switch %s: GT machine %s wasn't found"):format(sw.name, sw.machine)
      end
      if sw.source and not sourceNamed(sw.source) then
        out[#out + 1] = ("switch %s: its source %s isn't shown"):format(sw.name, sw.source)
      end
      if sw.lsc then
        local has = false
        for _, n in pairs(c.names) do if n == sw.lsc then has = true end end
        if not has then out[#out + 1] = ("switch %s follows %s, but no LSC has that name"):format(sw.name, sw.lsc) end
      end
    end
    for _, sw in ipairs(c.control) do
      local f = sw.fault
      if f then
        if not foundIn(ed.snap.redstone, f.redstone) then
          out[#out + 1] = ("switch %s: its fault input's redstone %s wasn't found"):format(sw.name, f.redstone)
        end
        local at = f.redstone .. " " .. tostring(Editor.sideName(f.side))
        if drives[at] then
          out[#out + 1] = ("switch %s reads its fault on redstone %s, which %s drives"):format(sw.name, at, drives[at])
        end
      end
    end
    for _, r in ipairs(ed.sourceRows()) do
      if not r.found then out[#out + 1] = ("source %s (%s) wasn't found - check its adapter, or drop it"):format(r.entry.name, r.key) end
    end
    if c.lensPort and not ed.snap.modem then out[#out + 1] = "LENS is on, but there's no network card" end
    return out
  end

  return ed
end

return Editor
