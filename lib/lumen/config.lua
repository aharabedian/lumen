--[[ lumen.config: /home/lumen.cfg, its defaults and checks. Every option: docs/configuration.md.

  DEFAULTS                       every setting and its default
  load(path) -> cfg | nil, err   The file is optional: without one, every default applies (cfg.missing = true).
                                 err is readable ("lowFill must be a percent, 0-100").
  check(cfg) -> cfg | nil, err   the same checks on a table (load uses it)
]]

local config = {}

config.DEFAULTS = {
  interval = 5,            -- seconds between readings
  names = {},              -- { ["d2440f27"] = "Main" }: start of an LSC's address -> its name on screen
  resolution = "fit",      -- "fit": fill the screen's shape; "max": the GPU's largest; { 80, 25 }: bigger characters
  lowFill = 25,            -- warn below this % full
  criticalFill = 10,       -- bad below this % full
  drainWarnHours = 4,      -- warn when draining and empty within this many hours
  drainBadHours = 1,       -- bad when empty within this many hours
  drainAverage = "1h",     -- which net average the drain alerts use: "5s", "5m" or "1h"
  inputDrop = nil,         -- warn when 5 min input falls this % below the hour's; nil: don't
  maxPassiveLoss = nil,    -- warn when an LSC's passive loss is above this many EU/t; nil: don't
  heatWarn = 25,           -- warn when a reactor is at this % of its max heat
  heatBad = 50,            -- bad at this %
  beep = true,             -- beep when a bad alert appears
  glanceAfter = 300,       -- big mode (few, big characters) after this many seconds without a tap or anyone near;
                           -- 0: only with BIG on the screen
  glanceScale = 3,         -- big mode's characters are this many times bigger
  wakeRange = 6,           -- blocks: a player this close to a Computronics radar wakes big mode (8 at most)
  wakePlayers = nil,       -- { "Steve" }: only these wake it; nil: anyone
  operators = nil,         -- { "Steve" }: only these can tap AUTO / ON / OFF, RESET and QUIT; nil: anyone
  sources = {},            -- { { address = "a1b2", name = "LFTR", alwaysOn = true }... }: GT generators to show
  control = {},            -- switches: { { name, redstone | machine, side, onBelow, offAbove, ... }... }
  supplies = {},           -- { { name, item = "gregtech:gt.reactorUraniumQuad", damage, below, above, hours, feeds }
                           --   or fluid = "ic2coolant" instead of item }: counted in an ME system
  groups = {},             -- { { name, steps = { { onBelow, offAbove, run }... }, rotate, lsc }... }: switches
                           -- that run together, as many as the fill needs (a switch joins with group = name)
  lensPort = nil,          -- report to LENS on this port (4243 is LENS's); nil: don't
  lensNode = "lumen",      -- this computer's name in LENS
  lensToken = nil,         -- LENS's token, if the hub has one
}

local function number(c, k, lo, hi, what)
  local v = c[k]
  if type(v) ~= "number" or v ~= v or v < lo or (hi and v > hi) then return k .. " must be " .. what end
end

function config.check(c)
  if type(c) ~= "table" then return nil, "the config must return a table" end
  for k, v in pairs(config.DEFAULTS) do
    if c[k] == nil then
      if type(v) == "table" then c[k] = {} else c[k] = v end
    end
  end
  local err = number(c, "interval", 1, nil, "a number of seconds, 1 or more")
    or number(c, "lowFill", 0, 100, "a percent, 0-100")
    or number(c, "criticalFill", 0, 100, "a percent, 0-100")
    or number(c, "drainWarnHours", 0, nil, "a number of hours")
    or number(c, "drainBadHours", 0, nil, "a number of hours")
  if err then return nil, err end
  if c.criticalFill > c.lowFill then return nil, "criticalFill must not be above lowFill" end
  if c.drainAverage ~= "5s" and c.drainAverage ~= "5m" and c.drainAverage ~= "1h" then
    return nil, 'drainAverage must be "5s", "5m" or "1h"'
  end
  if c.drainBadHours > c.drainWarnHours then return nil, "drainBadHours must not be above drainWarnHours" end
  if type(c.names) ~= "table" then return nil, 'names must be a table: { ["d2440f27"] = "Main" }' end
  for k, v in pairs(c.names) do
    if type(k) ~= "string" or k == "" or type(v) ~= "string" or v == "" then
      return nil, 'names: each entry is ["start of an address"] = "name"'
    end
  end
  do
    local r = c.resolution
    if r ~= "fit" and r ~= "max" and not (type(r) == "table" and math.type(r[1]) == "integer"
      and math.type(r[2]) == "integer" and r[1] >= 40 and r[2] >= 12) then
      return nil, 'resolution must be "fit", "max" or { width, height } (at least { 40, 12 })'
    end
  end
  if type(c.beep) ~= "boolean" then return nil, "beep must be true or false" end
  if type(c.glanceAfter) ~= "number" or (c.glanceAfter ~= 0 and c.glanceAfter < 10) then
    return nil, "glanceAfter must be a number of seconds, 10 or more, or 0 for only by hand"
  end
  if math.type(c.glanceScale) ~= "integer" or c.glanceScale < 2 or c.glanceScale > 6 then
    return nil, "glanceScale must be a whole number, 2-6"
  end
  if type(c.wakeRange) ~= "number" or c.wakeRange < 1 or c.wakeRange > 8 then
    return nil, "wakeRange must be a number of blocks, 1-8"
  end
  if c.operators ~= nil then
    if type(c.operators) ~= "table" then return nil, 'operators must be a list of names: { "Steve" }, or nil' end
    for _, n in ipairs(c.operators) do
      if type(n) ~= "string" or n == "" then return nil, 'operators must be a list of names: { "Steve" }, or nil' end
    end
  end
  if c.wakePlayers ~= nil then
    if type(c.wakePlayers) ~= "table" then return nil, 'wakePlayers must be a list of names: { "Steve" }, or nil' end
    for _, n in ipairs(c.wakePlayers) do
      if type(n) ~= "string" or n == "" then return nil, 'wakePlayers must be a list of names: { "Steve" }, or nil' end
    end
  end
  err = (c.inputDrop ~= nil and number(c, "inputDrop", 1, 100, "a percent, 1-100, or nil"))
    or (c.maxPassiveLoss ~= nil and number(c, "maxPassiveLoss", 0, nil, "a number of EU/t, or nil"))
    or number(c, "heatWarn", 0, 100, "a percent, 0-100")
    or number(c, "heatBad", 0, 100, "a percent, 0-100")
    or config.checkSources(c.sources)
    or config.checkGroups(c.groups)
    or config.checkSupplies(c.supplies)
    or config.checkControl(c.control, c.groups)
  if err then return nil, err end
  if c.heatWarn > c.heatBad then return nil, "heatWarn must not be above heatBad" end
  if c.lensPort ~= nil and (math.type(c.lensPort) ~= "integer" or c.lensPort < 1 or c.lensPort > 65535) then
    return nil, "lensPort must be 1-65535, or nil to not report to LENS"
  end
  if type(c.lensNode) ~= "string" or c.lensNode == "" then return nil, "lensNode must be a name" end
  if c.lensToken ~= nil and type(c.lensToken) ~= "string" then return nil, "lensToken must be text or nil" end
  return c
end

local function named(v) return type(v) == "string" and v ~= "" end

function config.checkSources(list)
  if type(list) ~= "table" then return 'sources must be a list: { { address = "a1b2", name = "LFTR" } }' end
  local names = {}
  for i, s in ipairs(list) do
    local where = ("sources[%d]"):format(i)
    if type(s) ~= "table" or not named(s.address) or not named(s.name) then
      return where .. ' needs an address (its start) and a name: { address = "a1b2", name = "LFTR" }'
    end
    if names[s.name] then return where .. ": another source is already called " .. s.name end
    names[s.name] = true
    if s.alwaysOn ~= nil and type(s.alwaysOn) ~= "boolean" then return where .. ".alwaysOn must be true or false" end
  end
end

local SIDES = { bottom = true, down = true, top = true, up = true, north = true, back = true, south = true,
  front = true, west = true, right = true, east = true, left = true }

local function percent(v, lo) return type(v) == "number" and v == v and v >= (lo or 0) and v <= 100 end

function config.checkSupplies(list)
  if type(list) ~= "table" then return 'supplies must be a list: { { name = "Fuel rods", item = "gregtech:..." } }' end
  local names = {}
  for i, s in ipairs(list) do
    if type(s) ~= "table" or not named(s.name) then return ("supplies[%d] needs a name"):format(i) end
    local where = ("supply %q"):format(s.name)
    if names[s.name] then return where .. ": two supplies have that name" end
    names[s.name] = true
    if named(s.item) == named(s.fluid) then
      return where .. ': needs item = "mod:registry_name" (with damage) or fluid = "name", one of them'
    end
    if s.damage ~= nil and math.type(s.damage) ~= "integer" then return where .. ": damage must be a whole number" end
    for _, k in ipairs({ "below", "above", "hours" }) do
      if s[k] ~= nil and (type(s[k]) ~= "number" or s[k] < 0) then return where .. ": " .. k .. " must be a number, 0 or more" end
    end
    if s.feeds ~= nil and not named(s.feeds) then return where .. ": feeds must be a name (what it feeds), or nil" end
  end
end

function config.checkGroups(list)
  if type(list) ~= "table" then return 'groups must be a list: { { name = "Nuclear", steps = { ... } } }' end
  local names = {}
  for i, g in ipairs(list) do
    if type(g) ~= "table" or not named(g.name) then return ("groups[%d] needs a name"):format(i) end
    local where = ("group %q"):format(g.name)
    if names[g.name] then return where .. ": two groups have that name" end
    names[g.name] = true
    if type(g.steps) ~= "table" or #g.steps == 0 then
      return where .. " needs steps: { { onBelow = 90, offAbove = 95, run = 4 }... }"
    end
    for k, st in ipairs(g.steps) do
      local at = ("%s step %d"):format(where, k)
      if type(st) ~= "table" or not percent(st.onBelow) or not percent(st.offAbove) then
        return at .. ": onBelow and offAbove must be percents, 0-100"
      end
      if st.onBelow >= st.offAbove then return at .. ": onBelow must be below offAbove" end
      if math.type(st.run) ~= "integer" or st.run < 1 then return at .. ": run must be a whole number, 1 or more" end
    end
    if g.rotate == nil then g.rotate = true end
    if type(g.rotate) ~= "boolean" then return where .. ": rotate must be true or false" end
    if g.lsc ~= nil and not named(g.lsc) then return where .. ": lsc must be an LSC's name (nil: all of them)" end
  end
end

function config.checkControl(list, groups)
  if type(list) ~= "table" then return "control must be a list of switches: { { name = ..., redstone = ... } }" end
  local groupNamed = {}
  for _, g in ipairs(groups or {}) do groupNamed[g.name] = true end
  local names = {}
  for i, s in ipairs(list) do
    local where = ("control[%d]"):format(i)
    if type(s) ~= "table" or not named(s.name) then return where .. " needs a name" end
    where = ("control %q"):format(s.name)
    if names[s.name] then return where .. ": two switches have that name" end
    names[s.name] = true
    if named(s.redstone) == named(s.machine) then
      return where .. ': needs redstone = "address start" (with a side) or machine = "address start", one of them'
    end
    if s.redstone then
      local side = s.side
      if not (SIDES[side] or (math.type(side) == "integer" and side >= 0 and side <= 5)) then
        return where .. ': side must be "bottom", "top", "north", "south", "west", "east" (or 0-5)'
      end
      if s.strength ~= nil and (math.type(s.strength) ~= "integer" or s.strength < 1 or s.strength > 15) then
        return where .. ": strength must be 1-15"
      end
      if s.invert ~= nil and type(s.invert) ~= "boolean" then return where .. ": invert must be true or false" end
    end
    if s.group ~= nil and not groupNamed[s.group] then return where .. (": group %q isn't in groups"):format(tostring(s.group)) end
    if s.always ~= nil and type(s.always) ~= "boolean" then return where .. ": always must be true or false" end
    if s.always and s.group then return where .. ": always or group, not both" end
    -- A group's members switch by its steps, and an always-on switch by the screen: their own marks are optional
    -- (kept for when they go back to them).
    if not ((s.group or s.always) and s.onBelow == nil and s.offAbove == nil) then
      for _, k in ipairs({ "onBelow", "offAbove" }) do
        if not percent(s[k]) then return where .. ": " .. k .. " must be a percent, 0-100" end
      end
      if s.onBelow >= s.offAbove then return where .. ": onBelow must be below offAbove" end
    end
    if s.heatTrip ~= nil and not percent(s.heatTrip, 1) then return where .. ": heatTrip must be a percent, 1-100, or nil" end
    if s.heatRise ~= nil and not (type(s.heatRise) == "number" and s.heatRise > 0) then
      return where .. ": heatRise must be a % of max heat a minute, above 0, or nil"
    end
    if s.minSwitch ~= nil and (type(s.minSwitch) ~= "number" or s.minSwitch < 0) then
      return where .. ": minSwitch must be a number of seconds"
    end
    if s.lsc ~= nil and not named(s.lsc) then return where .. ": lsc must be an LSC's name (nil: all of them)" end
    if s.source ~= nil and not named(s.source) then return where .. ": source must be a source's name" end
    if s.fault ~= nil then
      local f = s.fault
      if type(f) ~= "table" or not named(f.redstone) then
        return where .. ': fault needs redstone = "address start" (the component its signal comes into) and a side'
      end
      if not (SIDES[f.side] or (math.type(f.side) == "integer" and f.side >= 0 and f.side <= 5)) then
        return where .. ': fault: side must be "bottom", "top", "north", "south", "west", "east" (or 0-5)'
      end
      for _, k in ipairs({ "invert", "latch", "stop" }) do
        if f[k] ~= nil and type(f[k]) ~= "boolean" then return where .. ": fault: " .. k .. " must be true or false" end
      end
      if f.invert == nil then f.invert = false end
      if f.latch == nil then f.latch = false end
      if f.stop == nil then f.stop = true end
    end
  end
end

function config.load(path)
  local f = io.open(path, "r")
  if not f then
    local c = config.check({})
    c.missing = true
    return c
  end
  local text = f:read("*a")
  f:close()
  local chunk, err = load(text, "=" .. path, "t", {})
  if not chunk then return nil, err end
  local ok, c = pcall(chunk)
  if not ok then return nil, tostring(c) end
  return config.check(c)
end

return config
