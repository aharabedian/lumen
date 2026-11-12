--[[ lumen.telemetry: reporting to LENS, the base-wide monitoring hub (https://github.com/aharabedian/lens).
  Optional: off unless cfg.lensPort is set. Speaks lens/1 with LENS's own port and token. Metrics:
  docs/configuration.md.

  Telemetry.open(cfg, modem, log?) -> t | nil   nil when cfg.lensPort is off or there's no modem
  t.port
  t:announce()                     send the describe (the program does this once after open)
  t:report(readings, alerts)       after each reading: refresh the metrics and broadcast a snapshot
  t:handle(data)                   a packet that arrived on t.port: answers the hub's hello
  t:close()

  Each LSC is one `lsc` label: its name on screen. An LSC that can't be read reports lumen_lsc_up 0 and nothing
  else. Health is the worst alert's level.
]]

local computer = require("computer")
local metrics  = require("lumen.lens.metrics")
local codec    = require("lumen.lens.codec")

local Telemetry = {}
Telemetry.__index = Telemetry

function Telemetry.open(cfg, modem, log)
  local port = cfg.lensPort
  if not port or not modem then return nil end
  local t = setmetatable({ port = port, modem = modem, cfg = cfg }, Telemetry)
  local m = metrics.new{ role = "lumen", clock = computer.uptime }
  t.m = m
  t.up       = m:gauge("lumen_lsc_up", "1 when the LSC can be read, else 0")
  t.stored   = m:gauge("lumen_stored_eu", "EU stored", "EU")
  t.capacity = m:gauge("lumen_capacity_eu", "EU it can hold", "EU")
  t.fill     = m:gauge("lumen_fill_ratio", "How full: stored / capacity", "0..1")
  t.input    = m:gauge("lumen_input_eut", "EU/t in, averaged over 5 s", "EU/t")
  t.output   = m:gauge("lumen_output_eut", "EU/t out, averaged over 5 s", "EU/t")
  t.net      = m:gauge("lumen_net_eut", "EU/t in minus out, averaged over 5 s", "EU/t")
  t.net5m    = m:gauge("lumen_net_5m_eut", "EU/t in minus out, averaged over 5 min", "EU/t")
  t.net1h    = m:gauge("lumen_net_1h_eut", "EU/t in minus out, averaged over 1 hour", "EU/t")
  t.drain    = m:gauge("lumen_drain_seconds", "Seconds until empty at the net the drain alerts use (drainAverage)", "s")
  t.toFull   = m:gauge("lumen_full_seconds", "Seconds until full, while filling", "s")
  t.toEmpty  = m:gauge("lumen_empty_seconds", "Seconds until empty, while draining", "s")
  t.enc = codec.encoder{ node = cfg.lensNode, role = "lumen", boot = codec.newBoot(),
    interval = cfg.interval, token = cfg.lensToken, version = require("lumen.version") }
  modem.open(port)
  if log then log(("reporting to LENS as %s on port %d"):format(cfg.lensNode, port)) end
  return t
end

function Telemetry:broadcast(packets)
  for _, p in ipairs(packets) do self.modem.broadcast(self.port, p) end
end

function Telemetry:announce() self:broadcast(self.enc:describe(self.m:describe())) end

function Telemetry:report(readings, alerts)
  local m = self.m
  m:beginCycle()
  for _, r in ipairs(readings) do
    local l = { lsc = r.name }
    self.up:set(r.ok and 1 or 0, l)
    if r.ok then
      self.stored:set(r.stored, l)
      self.capacity:set(r.capacity, l)
      self.fill:set(r.fill, l)
      self.input:set(r.inEut, l)
      self.output:set(r.outEut, l)
      self.net:set(r.net, l)
      self.net5m:set(r.net5m, l)
      self.net1h:set(r.net1h, l)
      self.drain:set(r.drain and r.drain[self.cfg.drainAverage], l)
      self.toFull:set(r.full, l)
      self.toEmpty:set(r.empty, l)
    end
  end
  for _, a in ipairs(alerts) do m:alert(a.id, a.level, a.text) end
  self:broadcast(self.enc:snapshot(m:snapshot()))
end

function Telemetry:handle(data)
  local msg = codec.decode(data, self.cfg.lensToken)
  if msg and msg.kind == "hello" then
    self:broadcast(self.enc:describe(self.m:describe()))
    self:broadcast(self.enc:snapshot(self.m:snapshot()))
  end
end

function Telemetry:close() self.modem.close(self.port) end

return Telemetry
