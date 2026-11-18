--[[ lumen.history: what the LSCs did over time, kept small. Fill at three ranges for charts, and hourly
  totals for the last 48 hours. `time` is lumen.clock's (real seconds when it can tell, so history survives a
  restart through lumen.state).

  history.RANGES   { { name = "80 min", step = 30 }, { name = "8 h", step = 180 }, { name = "24 h", step = 540 } }:
                   SAMPLES samples each, a sample the average over its step
  history.SAMPLES  160
  history.new(saved?) -> h               saved: what h:save() returned (nil: empty)
  h:add(address, reading, time, dt)      one reading (address "" for the total). Fill into each range; EU in and
                                         out (inEut / outEut over dt seconds), the highest draw and lowest fill
                                         into this hour
  h:switch(name, on, time, dt)           a switch's time on, into this hour
  h:source(name, reading, time, dt)      a source (lumen.sources reading): its output into the 24 h range (an
                                         average per step), and into this hour: EU made, seconds running and
                                         read, starts (not counting the first reading after a start), the most
                                         EU/t while running
  h:flows(address) -> { { i, inE, outE }... }   an LSC's average EU/t in and out per 24 h step, oldest first
                                         (i: time // step; inE false where it wasn't kept)
  h:sourceChart(name) -> { { i, out }... }      a source's average EU/t per 24 h step, oldest first
  h:sourceDay(name, time) -> { eu, on, seen, starts, max }   the 24 hours up to `time`
  h:sourceMax(name) -> EU/t | nil        the most it made while running in the hours kept (48)
  h:keepSources(names)                   forget sources no longer there ({ [name] = true })
  h:supply(name, amount, time)           a supply's stock (lumen.supplies) into the 24 h range (an average per step)
  h:supplyChart(name) -> { { i, v }... }  its stock per 24 h step, oldest first
  h:supplyRate(name, time, seconds) -> per hour | nil   its change per hour over the last `seconds` (from the
                                         samples kept; nil until there's one that old, or 30 min at least)
  h:keepSupplies(names)                  forget supplies no longer there
  h:state(name, code, time)              a switch's state now ("on", "hand", "off", "handoff", "fault", "trip",
                                         "err", or "gone" while LUMEN isn't running): kept as changes, 7 days
  h:segments(name, from, to) -> { { from, to, state }... }   its states over [from, to], oldest first
  h:keepStates(names)                    forget switches no longer there
  h:sourceHours(time) -> { [hour] = true }   the hours (time // 3600) in the 24 up to `time` with sources kept
  h:inOver(address, hours) -> EU         an LSC's EU in over those hours
  h:chart(address, range) -> { fill... } oldest first (range: 1, 2 or 3)
  h:rate(address, seconds, time) -> EU/t   net over the last `seconds` (30 s samples; up to 80 min), nil without
                                         a sample that old
  h:day(address, time) -> { inEu, outEu, peakOut, peakAt, minFill, on = { [switch] = seconds }, hours }
                                         the 24 hours up to `time` (hours: how many have data). The day before:
                                         h:day(address, time - 86400)
  h:keep(addresses)                      forget LSCs no longer there ({ [address] = true })
  h:save() -> table                      plain numbers and strings, for lumen.state
]]

local history = {}

history.SAMPLES = 160
history.RANGES = { { name = "80 min", step = 30 }, { name = "8 h", step = 180 }, { name = "24 h", step = 540 } }
local HOURS = 48
local STATE_KEEP = 7 * 86400
local STATE_MAX = 300      -- changes kept per switch at most (memory)
local TICKS = 20

local H = {}
H.__index = H

function history.new(saved)
  local self = setmetatable({ lsc = {}, hours = {}, src = {}, running = {}, states = {}, sup = {} }, H)
  if type(saved) == "table" then
    self.lsc = type(saved.lsc) == "table" and saved.lsc or {}
    self.hours = type(saved.hours) == "table" and saved.hours or {}
    self.src = type(saved.src) == "table" and saved.src or {}
    self.states = type(saved.states) == "table" and saved.states or {}
    self.sup = type(saved.sup) == "table" and saved.sup or {}
  end
  -- History from before in and out were kept: unknown for the samples already there. And one saved after a
  -- sample begun by 0.2.1 crashed its finishing (a sample kept, its in and out not): lined up again.
  for _, l in pairs(self.lsc) do
    local rg = l[3]
    if rg then
      rg.inE, rg.outE = rg.inE or {}, rg.outE or {}
      for _, list in ipairs({ rg.inE, rg.outE }) do
        while #list < #rg.i do table.insert(list, 1, false) end
        while #list > #rg.i do table.remove(list, 1) end
      end
    end
  end
  return self
end

-- One LSC's ranges: per range { i = { bucket index... }, fill = {...}, stored = {...} (range 1), cur = { i, n,
-- fill, stored } (the bucket being averaged) }.
function H:ranges(address)
  local l = self.lsc[address]
  if not l then
    l = {}
    for k = 1, #history.RANGES do
      l[k] = { i = {}, fill = {}, stored = k == 1 and {} or nil, inE = k == 3 and {} or nil, outE = k == 3 and {} or nil }
    end
    self.lsc[address] = l
  end
  return l
end

local function push(rg, cur)
  rg.i[#rg.i + 1] = cur.i
  rg.fill[#rg.fill + 1] = math.floor(cur.fill / cur.n * 1e4 + 0.5) / 1e4
  if rg.stored then rg.stored[#rg.stored + 1] = cur.stored / cur.n end
  if rg.inE then        -- a sample begun by 0.2.1 has no in and out: unknown
    rg.inE[#rg.inE + 1] = cur.inE and math.floor(cur.inE / cur.n + 0.5) or false
    rg.outE[#rg.outE + 1] = cur.outE and math.floor(cur.outE / cur.n + 0.5) or false
  end
  if #rg.i > history.SAMPLES then
    table.remove(rg.i, 1)
    table.remove(rg.fill, 1)
    if rg.stored then table.remove(rg.stored, 1) end
    if rg.inE then table.remove(rg.inE, 1); table.remove(rg.outE, 1) end
  end
end

-- The hour bucket for `time` for `key` (an LSC's address, or "switch:" .. name).
function H:hour(key, time)
  local list = self.hours[key]
  if not list then list = {}; self.hours[key] = list end
  local h = math.floor(time / 3600)
  local last = list[#list]
  if last and last.h == h then return last end
  last = { h = h }
  list[#list + 1] = last
  while #list > HOURS or (list[1] and list[1].h <= h - HOURS) do table.remove(list, 1) end
  return last
end

function H:add(address, r, time, dt)
  if not (r and r.ok and r.fill) then return end
  for k, range in ipairs(history.RANGES) do
    local rg = self:ranges(address)[k]
    local i = math.floor(time / range.step)
    local cur = rg.cur
    if cur and cur.i ~= i then push(rg, cur); cur = nil end
    if not cur then cur = { i = i, n = 0, fill = 0, stored = 0, inE = 0, outE = 0 }; rg.cur = cur end
    cur.n, cur.fill, cur.stored = cur.n + 1, cur.fill + r.fill, cur.stored + (r.stored or 0)
    cur.inE, cur.outE = (cur.inE or 0) + (r.inEut or 0), (cur.outE or 0) + (r.outEut or 0)
  end
  local b = self:hour(address, time)
  if dt and dt > 0 then
    b.inEu = (b.inEu or 0) + (r.inEut or 0) * dt * TICKS
    b.outEu = (b.outEu or 0) + (r.outEut or 0) * dt * TICKS
  end
  if r.outEut and r.outEut > (b.peakOut or -1) then b.peakOut, b.peakAt = r.outEut, time end
  b.minFill = math.min(b.minFill or 1, r.fill)
end

function H:switch(name, on, time, dt)
  local b = self:hour("switch:" .. name, time)
  if on and dt and dt > 0 then b.on = (b.on or 0) + dt end
end

function H:source(name, r, time, dt)
  local running = r and r.ok and r.active and true or false
  local out = running and r.output or 0
  local step = history.RANGES[3].step
  local s = self.src[name]
  if not s then s = { i = {}, out = {} }; self.src[name] = s end
  local i = math.floor(time / step)
  local cur = s.cur
  if cur and cur.i ~= i then
    s.i[#s.i + 1], s.out[#s.out + 1] = cur.i, math.floor(cur.out / cur.n + 0.5)
    if #s.i > history.SAMPLES then table.remove(s.i, 1); table.remove(s.out, 1) end
    cur = nil
  end
  if not cur then cur = { i = i, n = 0, out = 0 }; s.cur = cur end
  cur.n, cur.out = cur.n + 1, cur.out + out
  local b = self:hour("source:" .. name, time)
  if dt and dt > 0 and r and r.ok then
    b.eu = (b.eu or 0) + out * dt * TICKS
    b.seen = (b.seen or 0) + dt
    if running then b.on = (b.on or 0) + dt end
  end
  if running and r.output and r.output > (b.max or 0) then b.max = r.output end
  if running and self.running[name] == false then b.starts = (b.starts or 0) + 1 end
  if r and r.ok then self.running[name] = running end
end

function H:flows(address)
  local rg = (self.lsc[address] or {})[3]
  if not rg then return {} end
  local out = {}
  for j, i in ipairs(rg.i) do out[#out + 1] = { i = i, inE = rg.inE and rg.inE[j], outE = rg.outE and rg.outE[j] } end
  local cur = rg.cur
  if cur and cur.inE then out[#out + 1] = { i = cur.i, inE = cur.inE / cur.n, outE = cur.outE / cur.n } end
  return out
end

function H:sourceChart(name)
  local s = self.src[name]
  if not s then return {} end
  local out = {}
  for j, i in ipairs(s.i) do out[#out + 1] = { i = i, out = s.out[j] } end
  if s.cur then out[#out + 1] = { i = s.cur.i, out = s.cur.out / s.cur.n } end
  return out
end

function H:sourceDay(name, time)
  local d = { eu = 0, on = 0, seen = 0, starts = 0 }
  local last = math.floor(time / 3600)
  for _, b in ipairs(self.hours["source:" .. name] or {}) do
    if b.h > last - 24 and b.h <= last then
      d.eu, d.on, d.seen, d.starts = d.eu + (b.eu or 0), d.on + (b.on or 0), d.seen + (b.seen or 0), d.starts + (b.starts or 0)
      if b.max and b.max > (d.max or 0) then d.max = b.max end
    end
  end
  return d
end

function H:sourceMax(name)
  local best
  for _, b in ipairs(self.hours["source:" .. name] or {}) do
    if b.max and b.max > (best or 0) then best = b.max end
  end
  return best
end

function H:sourceHours(time)
  local last, out = math.floor(time / 3600), {}
  for key, list in pairs(self.hours) do
    if key:find("^source:") then
      for _, b in ipairs(list) do if b.h > last - 24 and b.h <= last and (b.seen or 0) > 0 then out[b.h] = true end end
    end
  end
  return out
end

function H:inOver(address, hours)
  local sum = 0
  for _, b in ipairs(self.hours[address] or {}) do if hours[b.h] then sum = sum + (b.inEu or 0) end end
  return sum
end

function H:keepSources(names)
  for name in pairs(self.src) do if not names[name] then self.src[name], self.running[name] = nil, nil end end
  for key in pairs(self.hours) do
    local name = key:match("^source:(.*)$")
    if name and not names[name] then self.hours[key] = nil end
  end
end

function H:supply(name, amount, time)
  local step = history.RANGES[3].step
  local s = self.sup[name]
  if not s then s = { i = {}, v = {} }; self.sup[name] = s end
  local i = math.floor(time / step)
  local cur = s.cur
  if cur and cur.i ~= i then
    s.i[#s.i + 1], s.v[#s.v + 1] = cur.i, cur.v / cur.n
    if #s.i > history.SAMPLES then table.remove(s.i, 1); table.remove(s.v, 1) end
    cur = nil
  end
  if not cur then cur = { i = i, n = 0, v = 0 }; s.cur = cur end
  cur.n, cur.v = cur.n + 1, cur.v + amount
  s.last, s.lastAt = amount, time
end

function H:supplyChart(name)
  local s = self.sup[name]
  if not s then return {} end
  local out = {}
  for j, i in ipairs(s.i) do out[#out + 1] = { i = i, v = s.v[j] } end
  if s.cur then out[#out + 1] = { i = s.cur.i, v = s.cur.v / s.cur.n } end
  return out
end

function H:supplyRate(name, time, seconds)
  local s = self.sup[name]
  if not (s and s.last) then return nil end
  local step = history.RANGES[3].step
  local want = math.floor((time - seconds) / step)
  for j = #s.i, 1, -1 do
    if s.i[j] <= want then
      local dt = time - (s.i[j] + 0.5) * step
      if dt < 1800 then return nil end
      return (s.last - s.v[j]) / dt * 3600
    end
  end
  return nil
end

function H:keepSupplies(names)
  for name in pairs(self.sup) do if not names[name] then self.sup[name] = nil end end
end

function H:state(name, code, time)
  local list = self.states[name]
  if not list then list = {}; self.states[name] = list end
  local last = list[#list]
  if not last or last.s ~= code then list[#list + 1] = { t = time, s = code } end
  while #list > STATE_MAX or (list[2] and list[2].t <= time - STATE_KEEP) do table.remove(list, 1) end
end

function H:segments(name, from, to)
  local list, out = self.states[name] or {}, {}
  for k, c in ipairs(list) do
    local a, b = c.t, list[k + 1] and list[k + 1].t or to
    if b > from and a < to then out[#out + 1] = { from = math.max(a, from), to = math.min(b, to), state = c.s } end
  end
  return out
end

function H:keepStates(names)
  for name in pairs(self.states) do if not names[name] then self.states[name] = nil end end
end

function H:chart(address, k)
  local rg = (self.lsc[address] or {})[k or 1]
  if not rg then return {} end
  local out = { table.unpack(rg.fill) }
  if rg.cur then out[#out + 1] = rg.cur.fill / rg.cur.n end
  return out
end

function H:rate(address, seconds, time)
  local rg = (self.lsc[address] or {})[1]
  if not (rg and rg.cur) then return nil end
  local step = history.RANGES[1].step
  local nowI, nowStored = rg.cur.i, rg.cur.stored / rg.cur.n
  local want = math.floor((time - seconds) / step)
  for j = #rg.i, 1, -1 do
    if rg.i[j] <= want then
      local dt = (nowI - rg.i[j]) * step
      if dt <= 0 then return nil end
      return (nowStored - rg.stored[j]) / dt / TICKS
    end
  end
  return nil
end

function H:day(address, time)
  local d = { inEu = 0, outEu = 0, on = {}, hours = 0 }
  local last = math.floor(time / 3600)
  local function within(b) return b.h > last - 24 and b.h <= last end
  for _, b in ipairs(self.hours[address] or {}) do
    if within(b) then
      d.hours = d.hours + 1
      d.inEu, d.outEu = d.inEu + (b.inEu or 0), d.outEu + (b.outEu or 0)
      if b.peakOut and b.peakOut > (d.peakOut or -1) then d.peakOut, d.peakAt = b.peakOut, b.peakAt end
      if b.minFill then d.minFill = math.min(d.minFill or 1, b.minFill) end
    end
  end
  for key, list in pairs(self.hours) do
    local name = key:match("^switch:(.*)$")
    if name then
      for _, b in ipairs(list) do
        if within(b) then d.on[name] = (d.on[name] or 0) + (b.on or 0) end
      end
    end
  end
  return d
end

function H:keep(addresses)
  for address in pairs(self.lsc) do if not addresses[address] then self.lsc[address] = nil end end
  for key in pairs(self.hours) do
    if not key:find("^switch:") and not key:find("^source:") and not addresses[key] then self.hours[key] = nil end
  end
end

function H:save() return { lsc = self.lsc, hours = self.hours, src = self.src, states = self.states, sup = self.sup } end

return history
