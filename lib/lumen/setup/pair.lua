--[[ lumen.setup.pair: which IC2 reactor each redstone switch runs, found by running them one at a time. The only
  part of lumen-setup that switches anything: it turns every switch's output off, then each on alone until a
  reactor starts making power (or 15 s pass), then off again, and at the end puts every output back as it was.

  Pair.new(component, ed) -> p     ed: lumen.setup.editor (its switches and its snapshot's reactors)
  p:step(now) -> busy              do the next bit; call it every half second or so (each call reads every
                                   reactor once: a tick each)
  p:stop()                         every output back as it was, at once (STOP, an error, or leaving)
  p.rows = { { i (switch index), name, status, reactor (full address), took (seconds), was (its source before) }... }
    status: "waiting" | "testing" | "paired" | "none" (nothing started) | "many" (more than one started; not
    used) | "skipped" (a GT machine switch, or its fault input says trouble) | "stopped"
  p.current (the row testing), p.running (reactors already running at the start: never paired), p.done, p.err
  p:found() -> { { i, reactor }... }   the pairs to apply (status "paired")

  A switch is "on" as lumen.control drives it: strength 15 (or its strength), no signal when invert.
]]

local control = require("lumen.control")

local Pair = {}
Pair.__index = Pair

local WAIT, SETTLE, COOL = 15, 2, 5

local function sideOf(side) return type(side) == "number" and side or control.SIDES[side] end

function Pair.new(component, ed)
  local self = setmetatable({ component = component, ed = ed, rows = {}, saved = {}, running = {}, phase = "start" }, Pair)
  for i, sw in ipairs(ed.c.control) do
    self.rows[#self.rows + 1] = { i = i, name = sw.name, status = sw.redstone and "waiting" or "skipped",
      note = not sw.redstone and "a GT machine switch" or nil, was = sw.source }
  end
  self.reactors = {}
  for _, a in ipairs(ed.snap.reactors or {}) do self.reactors[#self.reactors + 1] = a end
  return self
end

function Pair:proxy(prefix, ctype)
  for address in self.component.list(ctype, true) do
    if address:sub(1, #prefix) == prefix then return self.component.proxy(address) end
  end
end

function Pair:write(sw, on)
  local p = self:proxy(sw.redstone, "redstone")
  if not p then error("no redstone component at " .. sw.redstone, 0) end
  p.setOutput(sideOf(sw.side), (on ~= (sw.invert == true)) and (sw.strength or 15) or 0)
end

-- Reactors making power now: { [address] = true }.
function Pair:active()
  local out = {}
  for _, a in ipairs(self.reactors) do
    local p = self.component.proxy(a)
    if p then
      local ok, v = pcall(function() return p.producesEnergy() end)
      if ok and v then out[a] = true end
    end
  end
  return out
end

function Pair:faulted(sw)
  local f = sw.fault
  if not f then return false end
  local p = self:proxy(f.redstone, "redstone")
  if not p then return false end
  local ok, v = pcall(p.getInput, sideOf(f.side))
  return ok and ((tonumber(v) or 0) > 0) ~= (f.invert == true)
end

function Pair:restore()
  for _, s in ipairs(self.saved) do pcall(s.proxy.setOutput, s.side, s.level) end
  self.saved = {}
end

function Pair:stop()
  self:restore()
  for _, r in ipairs(self.rows) do if r.status == "testing" or r.status == "waiting" then r.status = "stopped" end end
  self.current, self.done = nil, true
end

function Pair:nextRow()
  for _, r in ipairs(self.rows) do if r.status == "waiting" then return r end end
end

function Pair:step(now)
  if self.done then return false end
  local ok, err = pcall(function()
    local control_ = self.ed.c.control
    if self.phase == "start" then
      local seen = {}
      for _, r in ipairs(self.rows) do
        local sw = control_[r.i]
        local key = sw.redstone and (sw.redstone .. ":" .. tostring(sw.side))
        if key and not seen[key] then
          seen[key] = true
          local p = self:proxy(sw.redstone, "redstone")
          if p then
            local side = sideOf(sw.side)
            self.saved[#self.saved + 1] = { proxy = p, side = side, level = p.getOutput(side) }
          end
        end
      end
      for _, r in ipairs(self.rows) do
        local sw = control_[r.i]
        if sw.redstone and self:proxy(sw.redstone, "redstone") then self:write(sw, false)
        elseif sw.redstone then r.status, r.note = "skipped", "its redstone block isn't found" end
      end
      self.phase, self.at = "settle", now
    elseif self.phase == "settle" then
      if now - self.at < SETTLE then return end
      self.running = self:active()
      self.phase = "next"
    elseif self.phase == "next" then
      local r = self:nextRow()
      if not r then
        self:restore()
        self.current, self.done = nil, true
        return
      end
      local sw = control_[r.i]
      if self:faulted(sw) then r.status, r.note = "skipped", "its fault input says trouble"; return end
      self:write(sw, true)
      r.status, self.current, self.at, self.phase = "testing", r, now, "watch"
    elseif self.phase == "watch" then
      local r = self.current
      local started = {}
      for a in pairs(self:active()) do if not self.running[a] then started[#started + 1] = a end end
      table.sort(started)
      local waited = now - self.at
      if #started > 0 or waited >= WAIT then
        self:write(control_[r.i], false)
        if #started == 1 then r.status, r.reactor = "paired", started[1]
        elseif #started > 1 then r.status, r.note = "many", table.concat(started, ", ")
        else r.status = "none" end
        r.took = waited
        self.cooling = {}
        for _, a in ipairs(started) do self.cooling[a] = true end
        self.phase, self.at = "cool", now
      end
    elseif self.phase == "cool" then
      local still = false
      local act = self:active()
      for a in pairs(self.cooling or {}) do if act[a] then still = true end end
      if not still or now - self.at >= COOL then self.current, self.phase = nil, "next" end
    end
  end)
  if not ok then
    self.err = tostring(err)
    self:stop()
    return false
  end
  return not self.done
end

function Pair:found()
  local out = {}
  for _, r in ipairs(self.rows) do if r.status == "paired" then out[#out + 1] = { i = r.i, reactor = r.reactor } end end
  return out
end

return Pair
