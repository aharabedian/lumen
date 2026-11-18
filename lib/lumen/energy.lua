--[[ lumen.energy: the last 24 hours' energy, for its page. Where the EU came from (each group, each source not in
  one, and "other": what the LSCs took in that no source accounts for), where it went, and the headroom: what
  everything makes at full against the load. Pure: it reads lumen.history. "Other" counts only the hours that
  sources were kept, so it doesn't claim the hours before an update.

  energy.day(h, time, m) -> e
    h: lumen.history; m = { total, lscs (lumen.power readings), sources (lumen.sources list), groups (lumen.control
    c.groups) }. The LSCs: the total of several, or the only one.
    e = {
      step (seconds a sample covers), first, last (sample indices, time // step: the 24 hours up to `time`),
      bands = { {
        name, kind = "group" | "source" | "other", sources = { source name... }, members (a group's switches),
        samples = { [i] = EU/t }, eu (EU over the 24 h), share (0..1 of the bands' EU), on (0..1 of the time it was
        read that it ran; a group: its members' together), starts, avgOn (EU/t while running; a group: per
        member), full (EU/t at full: the most seen while running in the hours kept, a group's members added up;
        nil when none ran), unknown (sources never seen running) }... }   groups, then sources, then other
      came = { [i] = EU/t in }, load = { [i] = EU/t out }, made, used (EU in and out), hours (with readings),
      headroom = { full (EU/t, everything at full), unknown (sources never seen running), avg, peak (EU/t out),
        peakAt (time), spare (full - peak), unit = { name, each } (a group's member, to say "≈ 3 more"),
        making (EU/t now), load (EU/t out now) }
    }
]]

local history = require("lumen.history")

local energy = {}

local TICKS = 20
local OTHER = 0.01      -- "other" shows when it's more than this share of what came in

function energy.day(h, time, m)
  local step = history.RANGES[3].step
  local last = math.floor(time / step)
  local first = last - math.floor(86400 / step) + 1
  local e = { step = step, first = first, last = last, bands = {}, came = {}, load = {} }
  local r = m.total or (m.lscs and m.lscs[1])
  local address = r and r.address
  for _, f in ipairs(address and h:flows(address) or {}) do
    if f.i >= first and f.i <= last and f.inE then e.came[f.i], e.load[f.i] = f.inE, f.outE end
  end
  local day = address and h:day(address, time) or { inEu = 0, outEu = 0, hours = 0 }
  e.made, e.used, e.hours = day.inEu or 0, day.outEu or 0, day.hours or 0

  local grouped = {}
  for _, g in ipairs(m.groups or {}) do
    local names = {}
    for _, s in ipairs(g.members) do
      if s.source then names[#names + 1] = s.source; grouped[s.source] = true end
    end
    e.bands[#e.bands + 1] = { name = g.name, kind = "group", sources = names, members = #g.members }
  end
  for _, src in ipairs(m.sources or {}) do
    if not grouped[src.name] then e.bands[#e.bands + 1] = { name = src.name, kind = "source", sources = { src.name } } end
  end

  local hr = { full = 0, unknown = {} }
  local accounted = {}
  local sumEu = 0
  for _, b in ipairs(e.bands) do
    b.samples, b.eu, b.starts, b.unknown = {}, 0, 0, {}
    local on, seen, full = 0, 0, 0
    for _, name in ipairs(b.sources) do
      for _, p in ipairs(h:sourceChart(name)) do
        if p.i >= first and p.i <= last then
          b.samples[p.i] = (b.samples[p.i] or 0) + p.out
          accounted[p.i] = (accounted[p.i] or 0) + p.out
        end
      end
      local d = h:sourceDay(name, time)
      b.eu, b.starts, on, seen = b.eu + d.eu, b.starts + d.starts, on + d.on, seen + d.seen
      local most = h:sourceMax(name)
      if most then full = full + most else b.unknown[#b.unknown + 1] = name; hr.unknown[#hr.unknown + 1] = name end
    end
    b.on = seen > 0 and on / seen or nil
    b.avgOn = on > 0 and b.eu / (on * TICKS) or nil
    b.full = full > 0 and full or nil
    hr.full = hr.full + full
    sumEu = sumEu + b.eu
  end

  -- Other: what came in, over the hours sources were kept, that they don't account for (not the hours before
  -- LUMEN kept them, after an update).
  local otherEu = address and (h:inOver(address, h:sourceHours(time)) - sumEu) or 0
  if otherEu > (sumEu + otherEu) * OTHER then
    local o = { name = "other", kind = "other", sources = {}, samples = {}, eu = otherEu, starts = 0, unknown = {} }
    for i, v in pairs(e.came) do
      local rest = v - (accounted[i] or 0)
      if rest > 0 then o.samples[i] = rest end
    end
    e.bands[#e.bands + 1] = o
  end
  local total = sumEu + math.max(0, otherEu)
  for _, b in ipairs(e.bands) do b.share = total > 0 and b.eu / total or nil end

  local sum, n = 0, 0
  for _, v in pairs(e.load) do sum, n = sum + v, n + 1 end
  hr.avg = n > 0 and sum / n or nil
  hr.peak, hr.peakAt = day.peakOut, day.peakAt
  hr.spare = hr.peak and hr.full > 0 and hr.full - hr.peak or nil
  for _, b in ipairs(e.bands) do
    if b.kind == "group" and b.full and not hr.unit then
      local known = #b.sources - #b.unknown
      if known > 0 then hr.unit = { name = b.name, each = b.full / known } end
    end
  end
  local making = 0
  for _, src in ipairs(m.sources or {}) do if src.ok and src.active then making = making + (src.output or 0) end end
  hr.making, hr.load = making, r and r.ok and r.outEut or nil
  e.headroom = hr
  return e
end

return energy
