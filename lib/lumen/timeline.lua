--[[ lumen.timeline: the timeline page's model, from lumen.history and lumen.log. Pure.

  timeline.RANGES = { { name, span (seconds), chart (lumen.history range for the fill; nil: not kept that long) }... }
                    "8 H", "24 H", "7 D"
  timeline.FILTERS = { { id, name }... }   all, switches, faults, by hand, alerts (lumen.log's filters)
  timeline.code(s) -> state | nil   a lumen.control switch's state for lumen.history: "on", "hand" (on by hand),
                                    "off" (off in auto: standing by, above its mark), "handoff", "fault", "trip", "err"
  timeline.build(h, log, m, time, range, filter, cols) -> t
    m = { switches, total, lscs }; range: 1-3; cols: how many columns the bars get
    t = { range, span, from, to (time), fill = { [col] = 0..1 } | nil (at their times; none before it was kept),
          running = { 0..1... } (cols: the share of switches on), rows = { { name, cells = { state... } (cols),
          on (seconds on in the range) }... }, events (lumen.log's recent, filtered), filter }
    A cell shows the worst state in its time: a fault or trip, then an error, on by hand, on, off by hand, off;
    "gone" while LUMEN wasn't running; nil before it was kept.
]]

local timeline = {}

timeline.RANGES = { { name = "8 H", span = 8 * 3600, chart = 2 }, { name = "24 H", span = 86400, chart = 3 },
  { name = "7 D", span = 7 * 86400 } }
timeline.FILTERS = { { id = "all", name = "ALL" }, { id = "switches", name = "SWITCHES" }, { id = "faults", name = "FAULTS" },
  { id = "hand", name = "BY HAND" }, { id = "alerts", name = "ALERTS" } }

local RANK = { fault = 1, trip = 1, err = 2, hand = 3, on = 4, handoff = 5, off = 6, gone = 7 }

function timeline.code(s)
  if s.err then return "err" end
  if s.trip and s.trip.on then return "trip" end
  if s.fault and s.fault.on and s.cfg and s.cfg.fault and s.cfg.fault.stop ~= false then return "fault" end
  if s.on == nil then return nil end
  local manual = s.mode == "off" or (s.mode == "on" and not s.always)
  if s.on then return manual and "hand" or "on" end
  return manual and "handoff" or "off"
end

-- values (oldest first, one each `step` seconds, the last now) at their times on n columns spanning `span`
-- seconds up to now: nil where nothing was kept
local function place(values, step, span, n)
  local out, len = {}, #values
  if len == 0 then return nil end
  for c = 1, n do
    local back = (n - c + 0.5) * span / n             -- seconds before now at this column's middle
    local k = len - math.floor(back / step)
    out[c] = values[k]
  end
  return out
end

function timeline.build(h, log, m, time, range, filter, cols)
  local rg = timeline.RANGES[range] or timeline.RANGES[2]
  local t = { range = range, span = rg.span, from = time - rg.span, to = time, rows = {}, filter = filter or "all" }
  local r = m.total or (m.lscs and m.lscs[1])
  if rg.chart and r then
    t.fill = place(h:chart(r.address, rg.chart), require("lumen.history").RANGES[rg.chart].step, rg.span, cols)
  end
  local width = rg.span / cols
  local onCount = {}
  for _, s in ipairs(m.switches or {}) do
    local row = { name = s.name, cells = {}, on = 0 }
    for _, seg in ipairs(h:segments(s.name, t.from, time)) do
      if seg.state == "on" or seg.state == "hand" then row.on = row.on + (seg.to - seg.from) end
      local c1 = math.max(1, math.floor((seg.from - t.from) / width) + 1)
      local c2 = math.min(cols, math.floor((seg.to - t.from - 1e-6) / width) + 1)
      for c = c1, c2 do
        local cur = row.cells[c]
        if not cur or (RANK[seg.state] or 9) < (RANK[cur] or 9) then row.cells[c] = seg.state end
      end
    end
    for c = 1, cols do
      local st = row.cells[c]
      if st == "on" or st == "hand" then onCount[c] = (onCount[c] or 0) + 1 end
    end
    t.rows[#t.rows + 1] = row
  end
  local n = #t.rows
  t.running = {}
  for c = 1, cols do t.running[c] = n > 0 and (onCount[c] or 0) / n or 0 end
  t.events = log and log:recent(t.filter) or {}
  return t
end

return timeline
