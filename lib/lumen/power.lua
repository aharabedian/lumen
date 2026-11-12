--[[ lumen.power: finds the LSCs a computer can reach and reads them, through lumen.lsc.

  power.LSC                          what getName() returns for an LSC ("multimachine.supercapacitor")
  power.new(component, cfg) -> p    component: OpenOS `component`; cfg: lumen.config output (names)
  p:read() -> readings              every LSC, sorted by name then address. Each reading:
    { address, name, ok = true,
      stored, capacity (EU), fill (0..1),
      inEut, outEut, net (EU/t, the LSC's 5 s averages), net5m, net1h (EU/t),
      full | empty (seconds until full or empty: the LSC's own figure, else worked out from net5m),
      timeText (the LSC's own words, "10.42 hours"), maintenance ("ok", ...), passiveLoss (EU/t),
      drain = { ["5s"], ["5m"], ["1h"] }: seconds until empty at each average's net, nil where it isn't
              draining ("5s" is the LSC's own figure when it gives one) }
    or { address, name, ok = false, err } when it can't be read (unloaded chunk, broken adapter...)
  power.drain(reading) -> { ["5s"], ["5m"], ["1h"] }   time to empty at each average (readings have it)
  power.total(readings) -> reading | nil   the readable LSCs added up (name "All LSCs"); nil for fewer than 2
  power.duration(seconds) -> "10h 25m"

  Machines are checked with getName() once per address; other gt_machines are left alone. Only methods named
  get... are called: nothing here changes the game.
]]

local lsc = require("lumen.lsc")

local power = {}

power.LSC = "multimachine.supercapacitor"

local TICKS = 20

local P = {}
P.__index = P

function power.new(component, cfg)
  return setmetatable({ component = component, cfg = cfg or { names = {} }, kind = {} }, P)
end

function P:nameOf(address)
  for prefix, name in pairs(self.cfg.names or {}) do
    if address:sub(1, #prefix) == prefix then return name end
  end
  return "LSC " .. address:sub(1, 4)
end

-- Seconds to fill or empty `stored` of `capacity` at `net` EU/t.
local function eta(stored, capacity, net)
  if not (stored and net) or net == 0 then return nil, nil end
  if net > 0 then
    if not capacity then return nil, nil end
    return math.max(0, capacity - stored) / net / TICKS, nil
  end
  return nil, stored / -net / TICKS
end

local function call(proxy, name)
  if type(proxy[name]) ~= "function" then return nil end
  local ok, v = pcall(proxy[name])
  if ok then return v end
end

function P:readOne(address)
  local r = { address = address, name = self:nameOf(address) }
  local proxy = self.component.proxy(address)
  if not proxy then r.ok, r.err = false, "not connected"; return r end
  local ok, lines = pcall(proxy.getSensorInformation)
  if not ok or type(lines) ~= "table" then
    r.ok, r.err = false, ok and "no sensor information" or (tostring(lines):gsub("^[^:]*:%d+: ", ""))
    return r
  end
  local s = lsc.parse(lines)
  r.ok = true
  r.stored = s.stored or call(proxy, "getEUStored")
  r.capacity = s.capacity or call(proxy, "getEUMaxStored")
  r.fill = (r.stored and r.capacity and r.capacity > 0) and math.min(1, r.stored / r.capacity) or nil
  local avgIn, avgOut = s.avgIn or {}, s.avgOut or {}
  r.inEut, r.outEut = avgIn.sec, avgOut.sec
  local function minus(a, b) return (a and b) and a - b or nil end
  r.net, r.net5m, r.net1h = minus(avgIn.sec, avgOut.sec), minus(avgIn.min5, avgOut.min5), minus(avgIn.hour1, avgOut.hour1)
  r.maintenance, r.passiveLoss = s.maintenance, s.passiveLoss
  local t = s.timeTo
  if t then
    r.timeText = t.text
    if t.to == "full" then r.full = t.seconds elseif t.to == "empty" then r.empty = t.seconds end
  end
  if not (r.full or r.empty) then r.full, r.empty = eta(r.stored, r.capacity, r.net5m or r.net) end
  r.drain = power.drain(r)
  return r
end

function P:read()
  local out = {}
  for address in self.component.list("gt_machine", true) do
    if self.kind[address] == nil then
      local proxy = self.component.proxy(address)
      local ok, name = pcall(proxy and proxy.getName or error)
      if ok then self.kind[address] = name == power.LSC end
    end
    if self.kind[address] then out[#out + 1] = self:readOne(address) end
  end
  table.sort(out, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.address < b.address
  end)
  return out
end

-- Seconds until empty at each average's net; the LSC's own figure for 5 s when it has one.
function power.drain(r)
  local function at(net) return select(2, eta(r.stored, r.capacity, net)) end
  return { ["5s"] = (r.timeText and r.empty) or at(r.net), ["5m"] = at(r.net5m), ["1h"] = at(r.net1h) }
end

function power.total(readings)
  if #readings < 2 then return nil end
  local t = { name = "All LSCs", address = "", ok = true, stored = 0, capacity = 0, count = 0 }
  for _, field in ipairs({ "inEut", "outEut", "net", "net5m", "net1h", "passiveLoss" }) do t[field] = 0 end
  for _, r in ipairs(readings) do
    if r.ok then
      t.count = t.count + 1
      for _, field in ipairs({ "stored", "capacity", "inEut", "outEut", "net", "net5m", "net1h", "passiveLoss" }) do
        if t[field] and r[field] then t[field] = t[field] + r[field] else t[field] = nil end
      end
      if r.maintenance and r.maintenance ~= "ok" then t.maintenance = r.maintenance end
    end
  end
  if t.count == 0 then return { name = t.name, address = "", ok = false, err = "no LSC readable" } end
  t.maintenance = t.maintenance or "ok"
  t.fill = (t.stored and t.capacity and t.capacity > 0) and math.min(1, t.stored / t.capacity) or nil
  t.full, t.empty = eta(t.stored, t.capacity, t.net5m or t.net)
  t.drain = power.drain(t)
  return t
end

function power.duration(s)
  if not s then return nil end
  s = math.floor(s + 0.5)
  if s < 60 then return s .. "s" end
  if s < 3600 then return (s // 60) .. "m" end
  if s < 86400 then return ("%dh %02dm"):format(s // 3600, (s % 3600) // 60) end
  if s < 86400 * 365 then return ("%dd %dh"):format(s // 86400, (s % 86400) // 3600) end
  return "over a year"
end

return power
