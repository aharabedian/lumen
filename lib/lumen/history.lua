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
local TICKS = 20

local H = {}
H.__index = H

function history.new(saved)
  local self = setmetatable({ lsc = {}, hours = {} }, H)
  if type(saved) == "table" then
    self.lsc = type(saved.lsc) == "table" and saved.lsc or {}
    self.hours = type(saved.hours) == "table" and saved.hours or {}
  end
  return self
end

-- One LSC's ranges: per range { i = { bucket index... }, fill = {...}, stored = {...} (range 1), cur = { i, n,
-- fill, stored } (the bucket being averaged) }.
function H:ranges(address)
  local l = self.lsc[address]
  if not l then
    l = {}
    for k = 1, #history.RANGES do l[k] = { i = {}, fill = {}, stored = k == 1 and {} or nil } end
    self.lsc[address] = l
  end
  return l
end

local function push(rg, cur)
  rg.i[#rg.i + 1] = cur.i
  rg.fill[#rg.fill + 1] = math.floor(cur.fill / cur.n * 1e4 + 0.5) / 1e4
  if rg.stored then rg.stored[#rg.stored + 1] = cur.stored / cur.n end
  if #rg.i > history.SAMPLES then
    table.remove(rg.i, 1)
    table.remove(rg.fill, 1)
    if rg.stored then table.remove(rg.stored, 1) end
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
    if not cur then cur = { i = i, n = 0, fill = 0, stored = 0 }; rg.cur = cur end
    cur.n, cur.fill, cur.stored = cur.n + 1, cur.fill + r.fill, cur.stored + (r.stored or 0)
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
    if not key:find("^switch:") and not addresses[key] then self.hours[key] = nil end
  end
end

function H:save() return { lsc = self.lsc, hours = self.hours } end

return history
