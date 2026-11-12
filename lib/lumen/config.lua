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
  beep = true,             -- beep when a bad alert appears
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
  if c.lensPort ~= nil and (math.type(c.lensPort) ~= "integer" or c.lensPort < 1 or c.lensPort > 65535) then
    return nil, "lensPort must be 1-65535, or nil to not report to LENS"
  end
  if type(c.lensNode) ~= "string" or c.lensNode == "" then return nil, "lensNode must be a name" end
  if c.lensToken ~= nil and type(c.lensToken) ~= "string" then return nil, "lensToken must be text or nil" end
  return c
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
