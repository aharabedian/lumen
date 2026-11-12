--[[ tests/mocks/gen.lua - what LUMEN switches and reads besides LSCs, as OpenComputers shows them:

  local Gen = require("gen")
  local rs = Gen.redstone()            a Redstone I/O block or card: rs.out[side] (0-15), rs.sets (setOutput
                                       calls); rs.entry for M.components; rs.broken = "text": its calls raise
  local g = Gen.gt("gtpp.multimachine.lftr", { active = true, lines = { ... }, progress = 40, max = 100 })
                                       a GT generator (gt_machine): getSensorInformation returns state.lines;
                                       g.allowed (isWorkAllowed / setWorkAllowed), g.sets
  local r = Gen.reactor{ heat = 0, maxHeat = 10000, output = 1600, produces = true }
                                       an IC2 nuclear reactor ("reactor")

  The redstone component's API (getOutput / setOutput by side, 0-15) is OpenComputers' documented one. The GT
  generator's methods are those seen on an LSC; what its sensor lines say and the IC2 reactor's methods are
  assumptions until lumen-discover --read shows them (docs/architecture.md).
]]

local Gen = {}

function Gen.redstone()
  local rs = { out = {}, sets = 0 }
  local function guard() if rs.broken then error(rs.broken) end end
  rs.entry = { type = "redstone", methods = {
      getOutput = "function(side:number):number -- Get the redstone output on the specified side.",
      setOutput = "function(side:number, value:number):number -- Set the redstone output on the specified side.",
      getInput = "function(side:number):number -- Get the redstone input on the specified side.",
    }, proxy = {
      getOutput = function(side) guard(); assert(type(side) == "number", "side must be a number"); return rs.out[side] or 0 end,
      setOutput = function(side, value)
        guard()
        assert(type(side) == "number" and type(value) == "number", "setOutput(side, value)")
        local old = rs.out[side] or 0
        rs.out[side] = value
        rs.sets = rs.sets + 1
        return old
      end,
      getInput = function() return 0 end,
    } }
  return rs
end

function Gen.gt(name, state)
  local g = { state = state, allowed = true, sets = 0 }
  local function guard() if g.state.broken then error(g.state.broken) end end
  g.entry = { type = "gt_machine", methods = {
      getName = "function():string; Returns the machine's name",
      getSensorInformation = "function():table; Returns sensor information about this block",
      isMachineActive = "function():boolean; Returns whether the machine is currently active",
      isWorkAllowed = "function():boolean; Returns whether this block is currently allowed to work",
      setWorkAllowed = "function(work:boolean); Sets whether this block is currently allowed to work",
      getWorkProgress = "function():number; Returns the current progress of this block",
      getWorkMaxProgress = "function():number; Returns the max progress of this block",
    }, proxy = {
      getName = function() return name end,
      getSensorInformation = function() guard(); return g.state.lines or {} end,
      isMachineActive = function() guard(); return g.state.active and g.allowed end,
      isWorkAllowed = function() guard(); return g.allowed end,
      setWorkAllowed = function(v)
        guard()
        assert(type(v) == "boolean", "setWorkAllowed(boolean)")
        g.allowed = v
        g.sets = g.sets + 1
      end,
      getWorkProgress = function() return g.state.progress or 0 end,
      getWorkMaxProgress = function() return g.state.max or 0 end,
    } }
  return g
end

function Gen.reactor(state)
  local r = { state = state }
  local function guard() if r.state.broken then error(r.state.broken) end end
  r.entry = { type = "reactor", methods = {
      getHeat = "function():number -- Get the reactor's heat.",
      getMaxHeat = "function():number -- Get the reactor's maximum heat before exploding.",
      getReactorEUOutput = "function():number -- Get the reactor's EU output.",
      producesEnergy = "function():boolean -- Get whether the reactor is active and supposed to produce energy.",
    }, proxy = {
      getHeat = function() guard(); return r.state.heat end,
      getMaxHeat = function() guard(); return r.state.maxHeat end,
      getReactorEUOutput = function() guard(); return r.state.produces and r.state.output or 0 end,
      producesEnergy = function() guard(); return r.state.produces end,
    } }
  return r
end

return Gen
