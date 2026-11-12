--[[ lumen.setup.steps: lumen-setup's questions -> /home/lumen.cfg (and /home/.shrc).

  run(env)   env = { component, cfgPath, shrcPath }
    1. LSCs: a name for each one found
    2. Power sources: IC2 reactors (always shown: a name) and other GT machines (show it? a name; warn when it
       stops?). Configured sources that aren't found now can be kept
    3. Switches: keep the ones there are; add one: a redstone signal (which component, side, whether the signal
       means stop) or a GT machine's work switch; on below / off above; which LSC it follows; its source
    4. Alerts: fill, drain, input drop
    5. LENS: report or not, port, name, token
    6. Start on boot: a lumen line in .shrc (other lines are kept)
    Then shows the file and saves it after a yes, keeping the old one as .bak. Settings it doesn't ask about are
    kept. Raises input.CANCEL on Ctrl+D (nothing saved).
  sideLabels    the sides offered, in order
]]

local config = require("lumen.config")
local input  = require("lumen.setup.input")
local power  = require("lumen.power")
local render = require("lumen.setup.render")
local sources = require("lumen.sources")

local S = {}

S.SIDES = { "bottom", "top", "north", "south", "west", "east" }

-- Words in a GT machine's name that say it makes power: offered as a source by default.
local GENERATOR_WORDS = { "turbine", "generator", "lftr", "reactor", "dynamo", "combustion", "naquadah", "fuel",
  "solar", "plasma", "fusion", "boiler", "gas" }

local function short(address) return address:sub(1, 8) end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write(path, text)
  local f, err = io.open(path .. ".new", "w")
  if not f then return false, err end
  f:write(text)
  f:close()
  os.remove(path)
  return os.rename(path .. ".new", path)
end

local function nameFor(map, address)
  for prefix, name in pairs(map or {}) do
    if address:sub(1, #prefix) == prefix then return name, prefix end
  end
end

---------------------------------------------------------------- steps
local function lscStep(c, env)
  input.header("LSCs")
  local readings = power.new(env.component, { names = {} }):read()
  if #readings == 0 then
    print("  no LSC found: put an adapter next to an LSC's controller (touching this computer or cabled to it)")
    return readings
  end
  local names = {}
  for i, r in ipairs(readings) do
    local current, prefix = nameFor(c.names, r.address)
    local fill = r.ok and r.fill and ("%.1f%% full"):format(r.fill * 100) or "can't be read"
    print(("  LSC %s (%s)"):format(short(r.address), fill))
    local name = input.ask("    its name", current or (i == 1 and "Main" or ("LSC " .. r.address:sub(1, 4))))
    names[prefix or short(r.address)] = name
    r.name = name
  end
  -- Names for LSCs not found now (an unloaded chunk) are kept.
  for prefix, name in pairs(c.names or {}) do
    local found = false
    for _, r in ipairs(readings) do if r.address:sub(1, #prefix) == prefix then found = true end end
    if not found then names[prefix] = name end
  end
  c.names = names
  return readings
end

local function generatorish(name)
  local low = name:lower()
  for _, w in ipairs(GENERATOR_WORDS) do if low:find(w, 1, true) then return true end end
  return false
end

local function sourcesStep(c, env)
  input.header("Power sources")
  local have = {}
  for _, s in ipairs(c.sources or {}) do have[s.address] = s end
  local function configured(address)
    for prefix, s in pairs(have) do if address:sub(1, #prefix) == prefix then return s, prefix end end
  end
  local out, gts, seen = {}, {}, {}
  local found = {}
  for address, ctype in env.component.list() do found[#found + 1] = { address, ctype } end
  table.sort(found, function(a, b) return a[1] < b[1] end)
  for _, f in ipairs(found) do
    local address, ctype = f[1], f[2]
    local cur, prefix = configured(address)
    if sources.REACTORS[ctype] then
      print(("  an IC2 reactor (%s): shown with its heat and output"):format(short(address)))
      local name = input.ask("    its name", cur and cur.name or ("Reactor " .. address:sub(1, 4)))
      out[#out + 1] = { address = prefix or short(address), name = name }
      seen[prefix or short(address)] = true
    elseif ctype == "gt_machine" then
      local proxy = env.component.proxy(address)
      local ok, gtName = pcall(proxy and proxy.getName or error)
      gtName = ok and tostring(gtName) or "?"
      if gtName ~= power.LSC then
        gts[#gts + 1] = { address = address, name = gtName }
        if input.yes(("  show %s (%s) as a power source?"):format(gtName, short(address)), cur ~= nil or generatorish(gtName)) then
          local name = input.ask("    its name", cur and cur.name or gtName:gsub("^.*%.", ""))
          local always = input.yes("    warn when it stops for 5 minutes (it should always run)?", cur and cur.alwaysOn or false)
          out[#out + 1] = { address = prefix or short(address), name = name, alwaysOn = always or nil }
        end
        seen[prefix or short(address)] = true
      end
    end
  end
  for _, s in ipairs(c.sources or {}) do
    if not seen[s.address] and input.yes(("  keep %s (%s, not found now)?"):format(s.name, s.address), true) then
      out[#out + 1] = s
    end
  end
  if #out == 0 then print("  none: attach an adapter to a generator's controller or a reactor to show it") end
  c.sources = out
  return gts
end

local function newSwitch(env, readings, gts, srcList)
  local sw = {}
  sw.name = input.ask("    its name", "Generators")
  local how = input.choose({ "a redstone signal (Redstone I/O block or card; an SFM line, a reactor...)",
    "a GT machine's on/off (its work switch)" }, 1)
  if how == 1 then
    local list = {}
    for address in env.component.list("redstone", true) do list[#list + 1] = address end
    table.sort(list)
    if #list == 0 then
      print("    no redstone component found: attach a Redstone I/O block (or put a redstone card in), then run again")
      return nil
    end
    local labels = {}
    for _, a in ipairs(list) do labels[#labels + 1] = "redstone " .. short(a) end
    sw.redstone = short(list[#list == 1 and 1 or input.choose(labels, 1)])
    print("    which side does the signal go out of? (a Redstone I/O block: the world's directions)")
    sw.side = S.SIDES[input.choose(S.SIDES, 3)]
    if input.yes("    does a signal mean STOP (run while there's none)?", false) then sw.invert = true end
  else
    if #gts == 0 then print("    no GT machine found besides LSCs"); return nil end
    local labels = {}
    for _, g in ipairs(gts) do labels[#labels + 1] = ("%s (%s)"):format(g.name, short(g.address)) end
    sw.machine = short(gts[input.choose(labels, 1)].address)
  end
  sw.onBelow = input.number("    on below this % full", 30, 0, 99)
  sw.offAbove = input.number("    off above this % full", math.max(sw.onBelow + 1, 90), sw.onBelow + 1, 100)
  if #readings > 1 then
    local labels = { "all LSCs together" }
    for _, r in ipairs(readings) do labels[#labels + 1] = r.name end
    local k = input.choose(labels, 1)
    if k > 1 then sw.lsc = readings[k - 1].name end
  end
  if #srcList > 0 then
    print("    which source does it switch? (LUMEN warns when it's on and that isn't running)")
    local labels = { "none of them" }
    for _, s in ipairs(srcList) do labels[#labels + 1] = s.name end
    local k = input.choose(labels, 1)
    if k > 1 then sw.source = srcList[k - 1].name end
  end
  return sw
end

local function controlStep(c, env, readings, gts)
  input.header("Switches")
  print("  LUMEN can switch generators on when the LSCs run low and off when they're full.")
  local out = {}
  if #(c.control or {}) > 0 then
    for _, s in ipairs(c.control) do
      print(("  %s: %s, on below %g%%, off above %g%%"):format(s.name,
        s.redstone and ("redstone " .. s.redstone .. " " .. tostring(s.side)) or ("GT machine " .. tostring(s.machine)),
        s.onBelow, s.offAbove))
    end
    if input.yes("  keep these?", true) then out = c.control end
  end
  local srcList = {}
  for _, s in ipairs(c.sources or {}) do srcList[#srcList + 1] = s end
  while input.yes("  add a switch?", #out == 0 and #(c.control or {}) == 0 and false) do
    local sw = newSwitch(env, readings, gts, srcList)
    if sw then
      local dup = false
      for _, o in ipairs(out) do if o.name == sw.name then dup = true end end
      if dup then print("    there's already a switch called " .. sw.name)
      else out[#out + 1] = sw end
    end
  end
  c.control = out
end

local function alertsStep(c)
  input.header("Alerts")
  c.lowFill = input.number("  warn below this % full", c.lowFill or 25, 1, 100)
  c.criticalFill = input.number("  bad below this % full", math.min(c.criticalFill or 10, c.lowFill), 0, c.lowFill)
  c.drainWarnHours = input.number("  warn when it will be empty within this many hours", c.drainWarnHours or 4, 1, 1000)
  c.drainBadHours = input.number("  bad when within this many hours", math.min(c.drainBadHours or 1, c.drainWarnHours), 0,
    c.drainWarnHours)
  print("  An input alert says when input falls well below the hour's (a generator stopped). Generators that")
  print("  cycle by themselves (not through LUMEN's switches) would set it off: say no for those.")
  if input.yes("  warn when input falls by half?", c.inputDrop ~= nil) then c.inputDrop = c.inputDrop or 50
  else c.inputDrop = nil end
end

local function lensStep(c, env)
  input.header("LENS")
  if not env.component.isAvailable("modem") then
    print("  no network card: LUMEN can't report to LENS" .. (c.lensPort and " (lensPort kept)" or ""))
    return
  end
  if not input.yes("  report to a LENS hub?", c.lensPort ~= nil) then c.lensPort = nil; return end
  c.lensPort = input.number("  LENS port (the hub's port)", c.lensPort or 4243, 1, 65535)
  c.lensNode = input.ask("  this computer's name in LENS", c.lensNode or "lumen")
  local token = input.ask("  the hub's token (- for none)", c.lensToken)
  c.lensToken = (token ~= "-" and token) or nil
end

-- .shrc with the lumen line added or removed; other lines are kept. nil when nothing changes.
local function shrcText(path, want)
  local text = read(path) or ""
  local out, present = {}, false
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local word = line:match("^%s*(%S+)")
    local prog = word and word:gsub("^.*/", ""):gsub("%.lua$", "")
    if prog == "lumen" then present = true else out[#out + 1] = line end
  end
  if out[#out] == "" then out[#out] = nil end
  if want == present then return nil end
  if want then out[#out + 1] = "lumen" end
  return #out > 0 and (table.concat(out, "\n") .. "\n") or ""
end

local function loadOld(path)
  local text = read(path)
  if not text then return {} end
  local chunk, err = load(text, "=" .. path, "t", {})
  if not chunk then error(path .. " can't be read (" .. err .. "): fix or delete it first", 0) end
  local ok, c = pcall(chunk)
  if not ok or type(c) ~= "table" then error(path .. " can't be read: fix or delete it first", 0) end
  return c
end

function S.run(env)
  local c = loadOld(env.cfgPath)
  input.begin(6)
  local readings = lscStep(c, env)
  local gts = sourcesStep(c, env)
  controlStep(c, env, readings, gts)
  alertsStep(c)
  lensStep(c, env)
  input.header("Start on boot")
  local shrc = shrcText(env.shrcPath, input.yes("  start lumen when this computer boots?", true))

  for k, v in pairs(config.DEFAULTS) do
    if c[k] == nil and k ~= "lensToken" and k ~= "lensPort" and k ~= "inputDrop" and k ~= "maxPassiveLoss" then
      c[k] = type(v) == "table" and {} or v
    end
  end
  local text = render.cfg(c)
  -- What's saved must load: a mistake here is a bug in lumen-setup, not something to write.
  local chunk = load(text, "=lumen.cfg", "t", {})
  local ran, saved = pcall(chunk or error)
  local okCheck, why = config.check(ran and saved or nil)
  if not okCheck then error("lumen-setup made a config that doesn't load (" .. tostring(why) .. ") - please report it", 0) end

  print("")
  print("This will be saved to " .. env.cfgPath .. ":")
  io.write(text)
  if shrc then print(""); print("and " .. env.shrcPath .. " will be:"); io.write(shrc ~= "" and shrc or "(empty)\n") end
  if not input.yes("Save?", true) then print("nothing saved"); return false end
  local old = read(env.cfgPath)
  if old then
    local ok, err = write(env.cfgPath .. ".bak", old)
    if not ok then error("can't write " .. env.cfgPath .. ".bak: " .. tostring(err), 0) end
  end
  local ok, err = write(env.cfgPath, text)
  if not ok then error("can't write " .. env.cfgPath .. ": " .. tostring(err), 0) end
  if shrc then
    ok, err = write(env.shrcPath, shrc)
    if not ok then error("can't write " .. env.shrcPath .. ": " .. tostring(err), 0) end
  end
  print(("saved: %d LSC name(s), %d source(s), %d switch(es). Start lumen (or restart it) to use it."):format(
    #readings, #c.sources, #c.control))
  return true
end

return S
