--[[ lumen.control: switching generators on and off with the LSCs' fill. Each cfg.control entry is a switch:
  a redstone output (`redstone` = the start of a Redstone I/O block's or card's address, `side`, `invert`,
  `strength`), or a GT machine's work switch (`machine` = the start of its address; never an LSC). Only what the
  config names is ever switched. A switch may have a fault input (`fault` = { redstone, side, invert, latch,
  stop }): a redstone signal from whatever it runs that means trouble. LUMEN only reads it.

  control.SIDES                       side names -> OpenComputers side numbers (bottom 0 ... east 5)
  control.new(component, cfg, modes?, faults?) -> c
    modes: { [switch name] = "on" | "off" } kept from the last run (lumen.state); the rest start in "auto"
    faults: { [switch name] = true } latched faults kept from the last run
  c:update(readings, total, now)      decide, switch, read back; fills c.list
  c.list = { {
      name, mode = "auto" | "on" | "off", on = bool | nil (nil: can't tell), since (now when it last switched,
      or when LUMEN started), onBelow, offAbove, lsc (name followed; nil: all LSCs), source (name),
      fill (0..1 it follows, nil when unreadable), why (a few words: "below 30%", "holding: LSC unreadable"),
      err (text: can't be found or switched),
      fault = nil (no fault input) | { on (a fault now: the signal, or latched), signal (bool; nil: unreadable),
        latched, since (when it began), err (text: the input can't be read) } }... }   in cfg.control order
  c:setMode(name, mode, now)          from the screen: "auto", "on" or "off"; manual modes switch at once
  c:modes() -> { [name] = mode }      the manual ones, to keep across restarts
  c:reset(name, now)                  RESET on the screen: clears a latched fault once its signal is gone, and
                                      switches at once
  c:faults() -> { [name] = true }     the latched faults, to keep across restarts

  A fault (with stop, the default) switches off at once, whatever the mode, and holds it off while it lasts;
  once it clears, auto waits minSwitch as after any switch. latch: a fault stays until RESET. A fault input
  that can't be read is an error on the fault, and switches nothing.

  Auto: on below onBelow %, off above offAbove %, unchanged in between (so it doesn't flicker). It waits
  minSwitch seconds (default 60) after switching before switching again, and holds while it can't read the fill. On start it
  reads the output as it is, so a restart never flips anything. Each update reads the output back and sets it
  again if it differs (a redstone output resets when its chunk reloads).
]]

local power = require("lumen.power")

local control = {}

control.SIDES = { bottom = 0, down = 0, top = 1, up = 1, north = 2, back = 2, south = 3, front = 3,
  west = 4, right = 4, east = 5, left = 5 }

local C = {}
C.__index = C

local function reason(err) return (tostring(err):gsub("^[^:]*:%d+: ", "")) end

function control.new(component, cfg, modes, faults)
  local self = setmetatable({ component = component, cfg = cfg, list = {}, at = {} }, C)
  for _, sw in ipairs(cfg.control or {}) do
    local mode = modes and modes[sw.name]
    local latched = sw.fault and sw.fault.latch and faults and faults[sw.name] == true or false
    self.list[#self.list + 1] = { name = sw.name, mode = (mode == "on" or mode == "off") and mode or "auto",
      onBelow = sw.onBelow, offAbove = sw.offAbove, lsc = sw.lsc, source = sw.source, cfg = sw,
      fault = sw.fault and { on = latched, latched = latched } or nil }
  end
  return self
end

-- The component (address and proxy) whose address starts with `prefix`, of type `ctype`.
function C:resolve(prefix, ctype)
  local cached = self.at[prefix]
  if cached and self.component.proxy(cached) then return cached, self.component.proxy(cached) end
  for address in self.component.list(ctype, true) do
    if address:sub(1, #prefix) == prefix then
      self.at[prefix] = address
      return address, self.component.proxy(address)
    end
  end
end

local function sideOf(sw)
  if type(sw.side) == "number" then return sw.side end
  return control.SIDES[sw.side]
end

-- The output as it is: true (generators on), false, or nil, err.
function C:readOutput(s)
  local sw = s.cfg
  if sw.redstone then
    local _, proxy = self:resolve(sw.redstone, "redstone")
    if not proxy then return nil, "no redstone component at " .. sw.redstone end
    local ok, v = pcall(proxy.getOutput, sideOf(sw))
    if not ok then return nil, reason(v) end
    return ((tonumber(v) or 0) > 0) ~= (sw.invert == true)
  end
  local _, proxy = self:resolve(sw.machine, "gt_machine")
  if not proxy then return nil, "no GT machine at " .. sw.machine end
  local okName, name = pcall(proxy.getName)
  if okName and name == power.LSC then return nil, "that's an LSC: LUMEN never switches LSCs" end
  local ok, v = pcall(proxy.isWorkAllowed)
  if not ok then return nil, reason(v) end
  return v and true or false
end

-- The fault input: true (trouble), false, or nil, err.
function C:readFault(s)
  local f = s.cfg.fault
  local _, proxy = self:resolve(f.redstone, "redstone")
  if not proxy then return nil, "no redstone component at " .. f.redstone end
  local ok, v = pcall(proxy.getInput, sideOf(f))
  if not ok then return nil, reason(v) end
  return ((tonumber(v) or 0) > 0) ~= (f.invert == true)
end

function C:checkFault(s, now)
  local f = s.fault
  if not f then return end
  f.signal, f.err = self:readFault(s)
  if f.signal and s.cfg.fault.latch then f.latched = true end
  local on = f.signal == true or f.latched
  if on and (not f.on or not f.since) then f.since = now end   -- a latched fault kept from the last run: from now
  f.on = on
end

function C:writeOutput(s, on)
  local sw = s.cfg
  if sw.redstone then
    local _, proxy = self:resolve(sw.redstone, "redstone")
    local level = (on ~= (sw.invert == true)) and (sw.strength or 15) or 0
    local ok, err = pcall(proxy.setOutput, sideOf(sw), level)
    return ok, not ok and reason(err) or nil
  end
  local _, proxy = self:resolve(sw.machine, "gt_machine")
  local ok, err = pcall(proxy.setWorkAllowed, on)
  return ok, not ok and reason(err) or nil
end

-- The reading a switch follows: the LSC it names, else the total, else the only LSC.
local function followed(s, readings, total)
  if s.lsc then
    for _, r in ipairs(readings) do if r.name == s.lsc then return r end end
    return nil
  end
  return total or (#readings == 1 and readings[1]) or nil
end

local function decide(s, now, force)
  if s.fault and s.fault.on and s.cfg.fault.stop then return false, "fault: stopped" end
  if s.mode ~= "auto" then return s.mode == "on", "set " .. s.mode:upper() .. " on the screen" end
  if s.fill == nil then return s.on, "holding: can't read the LSC" end
  local pct = s.fill * 100
  local want, why = s.on, ("between %g%% and %g%%"):format(s.onBelow, s.offAbove)
  if pct < s.onBelow then want, why = true, ("below %g%%"):format(s.onBelow)
  elseif pct > s.offAbove then want, why = false, ("above %g%%"):format(s.offAbove) end
  if not force and want ~= s.on and s.on ~= nil and now - (s.switched or -math.huge) < (s.cfg.minSwitch or 60) then
    return s.on, "waiting to switch again"
  end
  if want == nil then want = true end      -- output unknown and between the marks: power first
  return want, why
end

function C:apply(s, now, force)
  local actual, err = self:readOutput(s)
  if actual == nil then s.on, s.err = nil, err; return end
  s.err = nil
  if s.on == nil then s.on, s.since = actual, s.since or now end   -- first look: as it is
  local want
  want, s.why = decide(s, now, force)
  if want == nil then return end
  if want ~= actual then
    local ok, werr = self:writeOutput(s, want)
    if not ok then s.err = werr; return end
  end
  if want ~= s.on then s.since, s.switched = now, now end
  s.on = want
end

function C:update(readings, total, now)
  for _, s in ipairs(self.list) do
    local r = followed(s, readings, total)
    s.fill = (r and r.ok and r.fill) or nil
    self:checkFault(s, now)
    self:apply(s, now)
  end
  return self.list
end

function C:setMode(name, mode, now)
  for _, s in ipairs(self.list) do
    if s.name == name and (mode == "auto" or mode == "on" or mode == "off") then
      s.mode = mode
      self:apply(s, now, true)           -- a choice on the screen doesn't wait for minSwitch
    end
  end
end

function C:reset(name, now)
  for _, s in ipairs(self.list) do
    if s.name == name and s.fault and s.fault.latched then
      s.fault.latched = false
      self:checkFault(s, now)
      self:apply(s, now, true)
    end
  end
end

function C:faults()
  local out = {}
  for _, s in ipairs(self.list) do if s.fault and s.fault.latched then out[s.name] = true end end
  return out
end

function C:modes()
  local out = {}
  for _, s in ipairs(self.list) do if s.mode ~= "auto" then out[s.name] = s.mode end end
  return out
end

return control
