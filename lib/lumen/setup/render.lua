--[[ lumen.setup.render: lumen.cfg as Lua source, with a comment on each setting.

  cfg(c) -> text     c: the config as it should be saved. Settings in a fixed order with comments, then names,
                     sources and control; keys it doesn't know are kept at the end.
  lua(v) -> text     any plain value as Lua source, keys in a stable order
]]

local VERSION = require("lumen.version")

local R = {}

local ORDER = { "name", "address", "redstone", "machine", "side", "invert", "strength", "onBelow", "offAbove", "lsc",
  "source", "alwaysOn", "minSwitch" }
local RANK = {}
for i, k in ipairs(ORDER) do RANK[k] = i end

local function keyRef(k)
  if type(k) == "string" and k:match("^[%a_][%w_]*$") then return k end
  return "[" .. R.lua(k) .. "]"
end

function R.lua(v)
  local t = type(v)
  if t == "string" then return ("%q"):format(v) end
  if t ~= "table" then return tostring(v) end
  local parts, n = {}, #v
  for i = 1, n do parts[#parts + 1] = R.lua(v[i]) end
  local keys = {}
  for k in pairs(v) do
    if not (math.type(k) == "integer" and k >= 1 and k <= n) then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b)
    local ra, rb = RANK[a] or 100, RANK[b] or 100
    if ra ~= rb then return ra < rb end
    return tostring(a) < tostring(b)
  end)
  for _, k in ipairs(keys) do parts[#parts + 1] = keyRef(k) .. " = " .. R.lua(v[k]) end
  if #parts == 0 then return "{}" end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local SETTINGS = {
  { "interval", "seconds between readings" },
  { "resolution", "{ width, height }: fewer, bigger characters; nil = the screen's largest" },
  { "lowFill", "warn below this % full" },
  { "criticalFill", "bad below this % full" },
  { "drainWarnHours", "warn when empty within this many hours (switches: see docs/configuration.md)" },
  { "drainBadHours", "bad when empty within this many hours" },
  { "drainAverage", '"5s", "5m" or "1h": the net drain alerts use without switches' },
  { "inputDrop", "warn when 5 min input falls this % below the hour's; nil = don't" },
  { "maxPassiveLoss", "warn when passive loss is above this EU/t; nil = don't" },
  { "heatWarn", "warn when a reactor is at this % of its max heat" },
  { "heatBad", "bad at this %" },
  { "beep", "beep when a bad alert appears" },
  { "lensPort", "report to LENS on this port; nil = don't" },
  { "lensNode", "this computer's name in LENS" },
  { "lensToken", "the LENS hub's token; nil = none" },
}

local function list(L, name, items, comment)
  L[#L + 1] = ""
  L[#L + 1] = "  -- " .. comment
  if #items == 0 then L[#L + 1] = ("  %s = {},"):format(name); return end
  L[#L + 1] = ("  %s = {"):format(name)
  for _, item in ipairs(items) do L[#L + 1] = "    " .. R.lua(item) .. "," end
  L[#L + 1] = "  },"
end

function R.cfg(c)
  local L = {
    "-- lumen.cfg - written by lumen-setup " .. VERSION .. ". Run lumen-setup to change it; values you edit by",
    "-- hand are kept when it rewrites this file (comments aren't). Every option: docs/configuration.md",
    "return {",
  }
  local known = { names = true, sources = true, control = true, missing = true }
  for _, s in ipairs(SETTINGS) do
    known[s[1]] = true
    local v = c[s[1]]
    local line = ("  %s = %s,"):format(s[1], v == nil and "nil" or R.lua(v))
    L[#L + 1] = ("%-34s -- %s"):format(line, s[2])
  end
  L[#L + 1] = ""
  L[#L + 1] = "  -- LSC names, by the start of their address"
  local addrs = {}
  for k in pairs(c.names or {}) do addrs[#addrs + 1] = k end
  table.sort(addrs)
  if #addrs == 0 then L[#L + 1] = "  names = {},"
  else
    L[#L + 1] = "  names = {"
    for _, k in ipairs(addrs) do L[#L + 1] = ("    [%q] = %s,"):format(k, R.lua(c.names[k])) end
    L[#L + 1] = "  },"
  end
  list(L, "sources", c.sources or {}, "power sources to show (GT generators; IC2 reactors show by themselves)")
  list(L, "control", c.control or {}, "switches: generators on below onBelow %, off above offAbove %")

  local extra = {}
  for k in pairs(c) do if not known[k] then extra[#extra + 1] = k end end
  table.sort(extra, function(a, b) return tostring(a) < tostring(b) end)
  if #extra > 0 then L[#L + 1] = "" end
  for _, k in ipairs(extra) do L[#L + 1] = ("  %s = %s,"):format(keyRef(k), R.lua(c[k])) end
  L[#L + 1] = "}"
  return table.concat(L, "\n") .. "\n"
end

return R
