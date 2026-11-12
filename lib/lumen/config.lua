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
  resolution = nil,        -- { 80, 25 }: fewer, bigger characters; nil: the screen's largest
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
  sources = {},            -- { { address = "a1b2", name = "LFTR", alwaysOn = true }... }: GT generators to show
  control = {},            -- switches: { { name, redstone | machine, side, onBelow, offAbove, ... }... }
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
  if c.resolution ~= nil then
    local r = c.resolution
    if type(r) ~= "table" or math.type(r[1]) ~= "integer" or math.type(r[2]) ~= "integer" or r[1] < 40 or r[2] < 12 then
      return nil, "resolution must be { width, height }, at least { 40, 12 }"
    end
  end
  if type(c.beep) ~= "boolean" then return nil, "beep must be true or false" end
  err = (c.inputDrop ~= nil and number(c, "inputDrop", 1, 100, "a percent, 1-100, or nil"))
    or (c.maxPassiveLoss ~= nil and number(c, "maxPassiveLoss", 0, nil, "a number of EU/t, or nil"))
    or number(c, "heatWarn", 0, 100, "a percent, 0-100")
    or number(c, "heatBad", 0, 100, "a percent, 0-100")
    or config.checkSources(c.sources)
    or config.checkControl(c.control)
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

function config.checkControl(list)
  if type(list) ~= "table" then return "control must be a list of switches: { { name = ..., redstone = ... } }" end
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
    for _, k in ipairs({ "onBelow", "offAbove" }) do
      if type(s[k]) ~= "number" or s[k] < 0 or s[k] > 100 then return where .. ": " .. k .. " must be a percent, 0-100" end
    end
    if s.onBelow >= s.offAbove then return where .. ": onBelow must be below offAbove" end
    if s.minSwitch ~= nil and (type(s.minSwitch) ~= "number" or s.minSwitch < 0) then
      return where .. ": minSwitch must be a number of seconds"
    end
    if s.lsc ~= nil and not named(s.lsc) then return where .. ": lsc must be an LSC's name (nil: all of them)" end
    if s.source ~= nil and not named(s.source) then return where .. ": source must be a source's name" end
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
