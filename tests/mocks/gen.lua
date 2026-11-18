--[[ tests/mocks/gen.lua - what LUMEN switches and reads besides LSCs, as OpenComputers shows them:

  local Gen = require("gen")
  local rs = Gen.redstone()            a Redstone I/O block or card: rs.out[side] (0-15), rs.sets (setOutput
                                       calls), rs.inp[side] (0-15, what getInput reads); rs.entry for
                                       M.components; rs.broken = "text": its calls raise
  local g = Gen.gt("gtpp.multimachine.lftr", { active = true, lines = { ... }, progress = 40, max = 100 })
                                       a GT generator (gt_machine): getSensorInformation returns state.lines;
                                       g.allowed (isWorkAllowed / setWorkAllowed), g.sets
  local r = Gen.reactor{ heat = 0, maxHeat = 10000, output = 1600, produces = true }
                                       an IC2 nuclear reactor ("reactor")

  local d = Gen.radar(players)         Computronics' radar block ("radar"): getPlayers([distance]) -> { { name,
                                       distance }... } within distance (8 at most), and each call takes 0.5 s;
                                       players = { { name, distance }... } (change it to move them); d.calls
  local d = Gen.detector(players)      OpenSecurity's entity detector ("os_entdetector"): scanPlayers([range]) ->
                                       { [1] = { name, range, x, y, z }... } within range / 2 (it halves the range
                                       it keeps on every call); d.calls
  Gen.MOTION                           OpenComputers' motion sensor ("motion_sensor"): an entry with no calls LUMEN
                                       uses; it sends { "motion", address, dx, dy, dz, name } events (tests send them)

  The radar's, entity detector's and motion sensor's behaviour is read from GTNH 2.9.0's sources (Computronics
  1.9.13, OpenSecurity 1.2.2, OpenComputers 1.12.68), not yet seen in game.

  The redstone component's API (getOutput / setOutput by side, 0-15) is OpenComputers' documented one. The GT
  generator's methods are those seen on an LSC; what its sensor lines say and the IC2 reactor's methods are
  assumptions until lumen-discover --read shows them (docs/architecture.md).
]]

local Gen = {}

function Gen.redstone()
  local rs = { out = {}, inp = {}, sets = 0 }
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
      getInput = function(side)
        guard(); assert(type(side) == "number", "side must be a number"); return rs.inp[side] or 0
      end,
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

function Gen.radar(players)
  local M = require("oc")
  local d = { players = players or {}, calls = 0 }
  d.entry = { type = "radar", methods = {
      getPlayers = "function([distance:number]):table; Returns a list of all players detected within the specified or the maximum range",
      getEntities = "function([distance:number]):table; Returns a list of all entities detected within the specified or the maximum range",
    }, proxy = {
      getPlayers = function(distance)
        d.calls = d.calls + 1
        M.time = M.time + 0.5                         -- context.pause(0.5)
        local r, out = math.min(tonumber(distance) or 8, 8), {}
        for _, p in ipairs(d.players) do if p.distance < r then out[#out + 1] = { name = p.name, distance = p.distance } end end
        return out
      end,
    } }
  return d
end

function Gen.detector(players)
  local d = { players = players or {}, calls = 0, range = 16 }
  d.entry = { type = "os_entdetector", methods = {
      scanPlayers = 'function(optional:int:range):table; pushes a signal "entityDetect" for each player in range, optional set range.',
    }, proxy = {
      scanPlayers = function(range)
        d.calls = d.calls + 1
        d.range = math.floor(math.min(tonumber(range) or d.range, 16) / 2)   -- kept, halved: a bare call shrinks it
        local out, i = {}, 1
        for _, p in ipairs(d.players) do
          if p.distance <= d.range then out[i] = { name = p.name, range = p.distance, x = 0, y = 0, z = 0 }; i = i + 1 end
        end
        return out
      end,
    } }
  return d
end

Gen.MOTION = { type = "motion_sensor", methods = {
  getSensitivity = "function():number -- Gets the current sensor sensitivity.",
  setSensitivity = "function(value:number):number -- Sets the sensor's sensitivity. Returns the old value.",
}, proxy = { getSensitivity = function() return 0.4 end, setSensitivity = function() return 0.4 end } }

return Gen
