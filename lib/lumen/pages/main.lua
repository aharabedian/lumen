--[[ lumen.pages.main: the main page. A panel per LSC (the total first; tap one for its page), the switches and
  sources ("POWER"), then alerts.

  POWER: each switch with its source, and each source no switch names, as TILES or ROWS (m.view; nil: tiles
  when there are 4 or more and they all fit, else rows). With groups, in sections: each group's line (how many
  run and are needed; tap it for lumen.pages.group) with its members under it, then "Not in a group". A tile:
  its title on its own colour (red for an error, fault, heat trip, or a source STILL RUNNING while its switch is
  off), what the source does and since when, its heat against its trip mark, why, and RESET (a latched fault or
  a trip) with AUTO / ON / OFF (ON / OFF for one that's always on). A row says the same on one line.

  main.build(f, m, actions)   f: lumen.frame; m, actions: lumen.screen's model and actions
  main.alerts(f, m, x, y, width, lastRow)   the alerts list (the detail page shows it too)

  Panels grow with the room they get: a name and figures line, a fill bar (up to six rows tall), flows (5 s
  averages), longer averages, and the fill history in the rows left. With 120 columns or more, several LSCs sit
  in two columns. Panels that don't fit end with "+N more"; so do alerts.
]]

local Gui = require("lumen.gui")
local power = require("lumen.power")
local frame = require("lumen.frame")

local main = {}

local C = frame.C
local si, signed, ago = frame.si, frame.signed, frame.ago

local function levelOf(r, alerts)
  local level
  for _, a in ipairs(alerts or {}) do
    if r.address ~= "" and a.id:sub(-#r.address - 1) == ":" .. r.address then
      if a.level == "bad" then return "bad" end
      level = "warn"
    end
  end
  return level
end

local function etaText(r)
  if r.full then return "full in " .. power.duration(r.full), C.good end
  if r.drainHow == "standby" and r.empty then return "standby, empty in " .. power.duration(r.empty), C.dim end
  if r.empty then return "empty in " .. power.duration(r.empty), C.warn end
  if r.fill and r.fill >= 0.9995 then return "full", C.good end
  return "steady", C.dim
end
main.etaText = etaText

local function panel(f, r, x, y, width, h, level, open)
  local color = level == "bad" and C.bad or level == "warn" and C.warn or C.text
  if open then f:hit(x, y, x + width - 1, y + h - 1, open) end
  if not r.ok then
    f:text(x, y, Gui.fit(r.name, width), C.accent)
    f:text(x, y + 1, Gui.fit("can't be read: " .. tostring(r.err), width), C.bad)
    return
  end
  local pct = r.fill and ("%.1f%%"):format(r.fill * 100) or "–"
  local figures = ("%s / %s EU  "):format(si(r.stored), si(r.capacity))
  f:text(x, y, Gui.fit(r.name, width - Gui.len(figures) - Gui.len(pct)), C.accent)
  f:text(x + width - Gui.len(figures) - Gui.len(pct), y, figures, C.dim)
  f:text(x + width - Gui.len(pct), y, pct, color)
  local barRows = h >= 6 and math.min(6, h - 4) or 1
  local last = y + h - 1
  f:bar(x, y + 1, width, barRows, r.fill, level == "bad" and C.bad or level == "warn" and C.warn or C.good)
  local row = y + barRows + 1
  if row <= last then
    local flows = ("in %s   out %s   net %s EU/t"):format(si(r.inEut), si(r.outEut), signed(r.net))
    local eta, etaColor = etaText(r)
    f:text(x, row, Gui.fit(flows, width - Gui.len(eta) - 1), C.text)
    f:text(x + width - Gui.len(eta), row, eta, etaColor)
    row = row + 1
  end
  if row <= last then
    local more = ("net 5 min %s   1 h %s EU/t"):format(signed(r.net5m), signed(r.net1h))
    local maint = r.maintenance == "ok" and "maintenance ok" or ("maintenance: " .. tostring(r.maintenance or "?"))
    if r.passiveLoss then maint = ("loss %s EU/t   "):format(si(r.passiveLoss)) .. maint end
    f:text(x, row, Gui.fit(more, width - Gui.len(maint) - 1), C.dim)
    f:text(x + width - Gui.len(maint), row, maint, r.maintenance == "ok" and C.dim or C.warn)
    row = row + 1
  end
  if row <= last and r.history and #r.history > 0 then f:chart(x, row, width, last - row + 1, r.history) end
end

---------------------------------------------------------------- POWER: switches and sources
local function faultText(f, s)
  local fl = s.fault
  if fl.err then return "fault input: " .. fl.err end
  local stops = s.cfg == nil or s.cfg.fault == nil or s.cfg.fault.stop ~= false
  local t = "fault signal" .. (stops and ", switched off" or ", still running")
  if fl.latched then t = t .. (fl.signal and "   latched" or "   gone: tap RESET") end
  if fl.since and f.now then t = t .. "   for " .. ago(f.now - fl.since) end
  return t
end

-- What a source is doing, as figures: "300.00k EU/t   heat 4%".
local function figures(src)
  local parts = {}
  if src.output then parts[#parts + 1] = si(src.output) .. " EU/t" end
  if src.heat then parts[#parts + 1] = ("heat %.0f%%"):format(src.heat * 100) end
  if src.progress then parts[#parts + 1] = ("recipe %.0f%%"):format(src.progress * 100) end
  if src.problems and src.problems > 0 then parts[#parts + 1] = src.problems .. " maintenance problems" end
  return table.concat(parts, "   ")
end

local SETTLE = 10   -- seconds a switch gets before its source disagreeing with it shows

-- The word for what a source is doing, its colour, and whether it disagrees with its switch s (nil: none).
local function sourceWord(f, s, src)
  if not src.ok then return "can't be read", C.bad, true end
  local settled = s and s.on ~= nil and (not s.since or not f.now or f.now - s.since >= SETTLE)
  if settled and s.on == false and src.active then return "STILL RUNNING", C.bad, true end
  if settled and s.on == true and not src.active then return "not running", C.warn, false end
  return src.active and "running" or "idle", src.active and C.good or C.dim, false
end

-- A switch's source, for its row: text, colour, and whether it disagrees with the switch.
local function sourceState(f, s, src)
  if not src.ok then return "can't be read: " .. tostring(src.err), C.bad, true end
  local word, colour, wrong = sourceWord(f, s, src)
  local fig = figures(src)
  return word .. (fig ~= "" and "   " .. fig or ""), colour, wrong
end

local function stateOf(s)
  if s.err then return "ERROR", C.bad end
  if s.trip and s.trip.on then return "TRIP", C.bad end
  if s.fault and s.fault.on then return "FAULT", C.bad end
  if s.on == nil then return "?", C.dim end
  return s.on and "ON" or "OFF", s.on and C.good or C.dim
end

-- Why a switch is as it is, and for how long (unless short).
local function detailOf(f, s, short)
  local function since(t, at) return (not short and at and f.now) and (t .. "   for " .. ago(f.now - at)) or t end
  if s.err then return s.err, C.bad end
  if s.trip and s.trip.on then return since("heat trip: " .. (s.trip.why or "heat"), s.trip.since), C.bad end
  if s.fault and (s.fault.on or s.fault.err) then return faultText(f, s), C.bad end
  local d
  if s.always and s.mode ~= "off" then d = s.why == "always on" and "always on: ON / OFF on the screen" or (s.why or "")
  elseif s.mode ~= "auto" then d = "by hand: " .. (s.why or "")
  elseif s.group then d = s.why or ("group " .. s.group)
  else
    d = ("auto: on below %g%%, off above %g%%"):format(s.onBelow, s.offAbove)
    if s.why and (s.why:find("^holding") or s.why:find("^waiting")) then d = d .. "   " .. s.why end
  end
  return since(d, s.since), C.dim
end

local function latched(s) return (s.fault and s.fault.latched) or (s.trip and s.trip.on) end

-- AUTO / ON / OFF ending at column xr; ON / OFF in the same places for a switch that's always on (ON is its auto).
local function modeButtons(f, xr, y, s, actions)
  local bx = xr - 16
  if s.always then
    bx = f:button(bx + 7, y, "ON", function() actions.mode(s.name, "auto") end, s.mode ~= "off")
  else
    bx = f:button(bx, y, "AUTO", function() actions.mode(s.name, "auto") end, s.mode == "auto")
    bx = f:button(bx - 1, y, "ON", function() actions.mode(s.name, "on") end, s.mode == "on")
  end
  f:button(bx - 1, y, "OFF", function() actions.mode(s.name, "off") end, s.mode == "off")
  return xr - 16
end

-- One row per switch, with what its source (when it names one) is doing: the switch's state, then the source's.
local function switchRow(f, s, src, x, y, width, actions)
  local srcText, srcColour, wrong
  if src then srcText, srcColour, wrong = sourceState(f, s, src) end
  local state, stateColour = stateOf(s)
  local running = src and src.ok and src.active or (not src and s.on)
  local dot = (stateColour == C.bad or wrong) and C.bad or (running and C.good) or C.dim
  f:text(x, y, "●", dot)
  f:text(x + 2, y, Gui.fit(s.name, 16), C.text)
  f:text(x + 19, y, Gui.fit(state, 5), stateColour)
  local bx = x + width - 18
  local resetX = latched(s) and bx - 8 or nil
  local detail, dcol = detailOf(f, s)
  local dx, room = x + 26, math.max(0, (resetX or bx) - x - 27)
  if srcText then
    -- the source first; the switch's detail after it when there's room (tier 2 has room for the source only)
    local sw = room >= 64 and 32 or room
    f:text(dx, y, Gui.fit(srcText, sw), srcColour)
    dx, room = dx + sw + 1, room - sw - 1
  end
  if room > 0 then f:text(dx, y, Gui.fit(detail, room), dcol) end
  if resetX then f:button(resetX, y, "RESET", function() actions.reset(s.name) end) end
  modeButtons(f, x + width - 1, y, s, actions)
end

-- A source no switch names: its own row.
local function sourceRow(f, src, x, y, width)
  local dot = not src.ok and C.bad or (src.active and C.good) or C.dim
  f:text(x, y, "●", dot)
  f:text(x + 2, y, Gui.fit(src.name, 16), C.text)
  if not src.ok then
    f:text(x + 19, y, Gui.fit("can't be read: " .. tostring(src.err), width - 19), C.bad)
    return
  end
  f:text(x + 19, y, Gui.fit(src.active and "running" or "idle", 9), dot)
  f:text(x + 29, y, Gui.fit(figures(src), width - 29), C.dim)
end

---------------------------------------------------------------- tiles
local TILE_H, TILE_MIN = 5, 36

local function tileGrid(width)
  local cols = math.max(1, (width + 2) // (TILE_MIN + 2))
  return cols, (width - (cols - 1) * 2) // cols
end

-- A switch and its source (or a source alone) as a tile w wide, TILE_H tall: a title on its own colour (red for
-- trouble), what the source does and for how long, its heat against the trip mark, why, then RESET and buttons.
local function tile(f, it, x, y, w, m, actions)
  local s, src, P = it.s, it.src, C.panel
  local word, wcol, wrong = "", C.dim, false
  if src then word, wcol, wrong = sourceWord(f, s, src) end
  local state, scol = "", C.dim
  if s then state, scol = stateOf(s) end
  local red = scol == C.bad or wrong
  local tb, tf = red and C.bad or C.line, red and C.bg or C.text
  f:text(x, y, string.rep(" ", w), C.text, tb)
  for r = 1, TILE_H - 1 do f:text(x, y + r, string.rep(" ", w), C.text, P) end
  local running = (src and src.ok and src.active) or (not src and s and s.on)
  f:text(x + 1, y, "●", red and C.bg or (running and C.good or C.dim), tb)
  local badge = "no switch"
  if s then
    local how
    if s.mode == "off" or (s.mode == "on" and not s.always) then how = "by hand"
    elseif s.always then how = "always"
    elseif s.group then if state == "OFF" then state = "STANDBY" end   -- its section names the group
    else how = "auto" end
    if state == "FAULT" and s.fault.latched then how = "latched" end
    badge = (state == "TRIP" or state == "ERROR" or not how) and state or (state .. " · " .. how)
  end
  f:text(x + 3, y, Gui.fit(s and s.name or src.name, w - Gui.len(badge) - 6), tf, tb)
  f:text(x + w - 1 - Gui.len(badge), y, badge, red and C.bg or (scol ~= C.dim and scol or C.dim), tb)

  local since = s and s.since and f.now and ("for " .. ago(f.now - s.since)) or ""
  if src and not src.ok then
    f:text(x + 1, y + 1, Gui.fit("can't be read: " .. tostring(src.err), w - 2), C.bad, P)
  elseif src then
    f:text(x + 1, y + 1, word, wcol, P)
    local eu = src.output and (si(src.output) .. " EU/t") or ""
    f:text(x + 16, y + 1, Gui.fit(eu, w - 17 - Gui.len(since) - 1), running and C.text or C.dim, P)
  end
  if since ~= "" then f:text(x + w - 1 - Gui.len(since), y + 1, since, C.dim, P) end

  if src and src.ok and src.heat then
    local mark = s and s.trip and (s.trip.rearm or s.cfg.heatTrip)
    local pct = src.heat * 100
    local hot = mark and pct >= mark - 5
    local tail = mark and ("trip %g%%"):format(mark) or ""
    local bw = w - 13 - Gui.len(tail)
    f:text(x + 1, y + 2, "heat", C.dim, P)
    f:bar(x + 6, y + 2, bw, 1, pct / (mark or 100), hot and C.warn or C.info)
    f:text(x + 6 + bw + 1, y + 2, Gui.rfit(("%.0f%%"):format(pct), 4), hot and C.warn or C.text, P)
    if mark then f:text(x + w - 1 - Gui.len(tail), y + 2, tail, C.dim, P) end
  elseif src and src.ok and src.progress then
    f:text(x + 1, y + 2, "recipe", C.dim, P)
    f:bar(x + 8, y + 2, w - 15, 1, src.progress, C.info)
    f:text(x + w - 5, y + 2, Gui.rfit(("%.0f%%"):format(src.progress * 100), 4), C.text, P)
  end

  local note, ncol = "", C.dim
  if s then note, ncol = detailOf(f, s, true)
  elseif src and src.ok and src.problems and src.problems > 0 then note, ncol = src.problems .. " maintenance problems", C.warn end
  if wrong and src and src.ok then note, ncol = "switched off, but it still makes power", C.bad end
  f:text(x + 1, y + 3, Gui.fit(note, w - 2), ncol, P)

  if s then
    local hrs = m.hours and m.hours[s.name]
    if latched(s) then f:button(x + 1, y + 4, "RESET", function() actions.reset(s.name) end)
    elseif hrs then f:text(x + 1, y + 4, "24 h: on " .. ago(hrs), C.dim, P) end
    modeButtons(f, x + w - 2, y + 4, s, actions)
  end
end

---------------------------------------------------------------- the section
-- A group's line: how many run and are needed; tap it for the group's page.
local function groupLine(f, g, x, y, width, actions)
  f:text(x, y, "▸ " .. Gui.fit(g.name, 16), C.accent)
  local t
  if g.need == nil then t = g.why or "starting"
  else
    local lowest
    for _, st in ipairs(g.steps) do if st.active and (not lowest or st.onBelow < lowest) then lowest = st.onBelow end end
    t = ("%d of %d running   %d needed%s"):format(g.running or 0, #g.members, g.need,
      lowest and (" below %g%%"):format(lowest) or "")
    if g.why and g.why:find("^holding") then t = t .. "   " .. g.why end
  end
  f:text(x + 20, y, Gui.fit(t, width - 20), C.text)
  local hint = "tap for its ladder and order"
  local hx = x + 20 + Gui.len(t) + 3
  if hx + Gui.len(hint) <= x + width then f:text(hx, y, hint, C.dim) end
  f:hit(x, y, x + width - 1, y, function() actions.group(g.name) end)
end

-- POWER's sections: each group with its members, then the rest ({ group = nil, title = "Not in a group" }): the
-- switches in lumen.cfg's order, then the sources no switch names. titled: draw the sections' lines (with groups).
local function powerSections(m)
  local byName, used = {}, {}
  for _, src in ipairs(m.sources or {}) do byName[src.name] = byName[src.name] or src end
  local out, byGroup = {}, {}
  for _, g in ipairs(m.groups or {}) do
    out[#out + 1] = { group = g, items = {} }
    byGroup[g.name] = out[#out]
  end
  local rest = { title = "Not in a group", items = {} }
  for _, s in ipairs(m.switches or {}) do
    local src = s.source and byName[s.source]
    if src then used[src] = true end
    local sec = s.group and byGroup[s.group] or rest
    sec.items[#sec.items + 1] = { s = s, src = src }
  end
  for _, src in ipairs(m.sources or {}) do if not used[src] then rest.items[#rest.items + 1] = { src = src } end end
  if #rest.items > 0 then out[#out + 1] = rest end
  return out, #(m.groups or {}) > 0
end

-- Walk the sections from row `top` to `last` the way L lays them out, calling draw(kind, thing, y, col) when given
-- ("header", section; "tile", item; "row", item). -> the last row used, how many items fit
local function walk(secs, titled, L, top, last, draw)
  local y, used, shown = top, top - 1, 0
  for _, sec in ipairs(secs) do
    if titled then
      if y > last then return used, shown end
      if draw then draw("header", sec, y) end
      used, y = y, y + 1
    end
    if L.view == "tiles" then
      for k = 1, #sec.items, L.cols do
        if y + TILE_H - 1 > last then return used, shown end
        for c = 0, L.cols - 1 do
          local it = sec.items[k + c]
          if it then
            if draw then draw("tile", it, y, c) end
            shown = shown + 1
          end
        end
        used, y = y + TILE_H - 1, y + TILE_H + L.gap
      end
    else
      for _, it in ipairs(sec.items) do
        if y > last then return used, shown end
        if draw then draw("row", it, y) end
        used, y, shown = y, y + 1, shown + 1
      end
    end
  end
  return used, shown
end

-- How POWER is laid out in at most `cap` rows: { view, rows, gap (between tile rows), cols, tw, hidden }.
local function powerLayout(m, secs, titled, width, cap, h)
  local cols, tw = tileGrid(width)
  local L = { cols = cols, tw = tw }
  local total = 0
  for _, sec in ipairs(secs) do total = total + #sec.items end
  local function need(view, gap)
    L.view, L.gap = view, gap
    return (walk(secs, titled, L, 2, math.huge))
  end
  local gap = need("tiles", 1) <= cap and 1 or 0
  local view = m.view
  if not view then view = (total >= 4 and need("tiles", gap) <= cap) and "tiles" or "rows" end
  L.view, L.gap = view, view == "tiles" and gap or 0
  local limit = view == "tiles" and cap or math.max(2, math.min(cap, h // 2))
  local used, shown = walk(secs, titled, L, 2, limit)
  L.rows, L.hidden = math.max(1, used), total - shown
  return L
end

local function sectionLine(f, sec, x, y, width, actions)
  if sec.group then return groupLine(f, sec.group, x, y, width, actions) end
  f:text(x + 2, y, sec.title, C.accent)
  local always, alone = 0, 0
  for _, it in ipairs(sec.items) do
    if it.s and it.s.always then always = always + 1 elseif not it.s then alone = alone + 1 end
  end
  local parts = {}
  if always > 0 then parts[#parts + 1] = ("%d always on"):format(always) end
  if #sec.items - always - alone > 0 then parts[#parts + 1] = ("%d by their own marks"):format(#sec.items - always - alone) end
  if alone > 0 then parts[#parts + 1] = ("%d with no switch"):format(alone) end
  f:text(x + 20, y, Gui.fit(table.concat(parts, " · "), width - 20), C.dim)
end

local function powerSection(f, m, secs, titled, L, x, y, width, actions)
  walk(secs, titled, L, y + 1, y + L.rows - 1, function(kind, thing, ry, col)
    if kind == "header" then sectionLine(f, thing, x, ry, width, actions)
    elseif kind == "tile" then tile(f, thing, x + col * (L.tw + 2), ry, L.tw, m, actions)
    elseif thing.s then switchRow(f, thing.s, thing.src, x, ry, width, actions)
    else sourceRow(f, thing.src, x, ry, width) end
  end)

  f:text(x, y, "POWER", C.accent)
  local n, on, eu, any = 0, 0, 0, 0
  for _, sec in ipairs(secs) do
    for _, it in ipairs(sec.items) do
      any = any + 1
      if it.src then
        n = n + 1
        if it.src.ok and it.src.active then on, eu = on + 1, eu + (it.src.output or 0) end
      end
    end
  end
  local t = n > 0 and ("%d of %d running   %s EU/t"):format(on, n, si(eu)) or ""
  if L.hidden > 0 then t = t .. ("   +%d more %s"):format(L.hidden, L.view == "tiles" and "tiles" or "rows") end
  f:text(x + 7, y, Gui.fit(t, math.max(0, width - 7 - 16)), C.dim)
  if any >= 2 then
    local bx = f:button(x + width - 15, y, "TILES", function() actions.view("tiles") end, L.view == "tiles")
    f:button(bx - 1, y, "ROWS", function() actions.view("rows") end, L.view == "rows")
  end
end

function main.alerts(f, m, x, y, width, lastRow)
  local list = m.alerts or {}
  f:text(x, y, Gui.fit(("ALERTS (%d)"):format(#list), width), C.accent)
  y = y + 1
  if #list == 0 then
    f:text(x, y, "All good.", C.dim)
    return
  end
  local room = lastRow - y + 1
  local shown = math.min(#list, room)
  if shown < #list then shown = room - 1 end
  for i = 1, shown do
    local a = list[i]
    f:text(x, y, Gui.fit(a.level == "bad" and " BAD" or " WARN", 6), C.bg, a.level == "bad" and C.bad or C.warn)
    f:text(x + 7, y, Gui.fit(a.text, width - 7 - 7), C.text)
    f:text(x + width - 6, y, Gui.rfit(ago(m.now - (a.since or m.now)), 6), C.dim)
    y = y + 1
  end
  if shown < #list then f:text(x, y, ("+%d more"):format(#list - shown), C.dim) end
end

function main.build(f, m, actions)
  local width = f.w - 2
  local nAlerts = #(m.alerts or {})
  local alertRows = math.max(2, math.min(nAlerts + 1, math.max(2, f.h // 4)))
  local alertTop = f.h - alertRows
  local secs, titled = powerSections(m)
  local L = powerLayout(m, secs, titled, width, math.max(2, alertTop - 7), f.h)   -- the LSCs keep at least two rows
  local powerRows = #secs > 0 and L.rows or 0
  local powerTop = alertTop - powerRows - (powerRows > 0 and 1 or 0)
  local top, bottom = 3, powerTop - 2       -- panels go in rows top..bottom

  if #m.lscs == 0 then
    f:text(2, top, Gui.fit("No LSC found. Put an adapter next to an LSC's controller block,", width), C.dim)
    f:text(2, top + 1, Gui.fit("touching this computer or connected to it with cable.", width), C.dim)
  else
    local cols = (f.w >= 120 and #m.lscs >= 2) and 2 or 1
    local gridRows = (#m.lscs + cols - 1) // cols + (m.total and 1 or 0)
    local h = math.max(2, math.min(40, (bottom - top + 2) // gridRows - 1))
    local y = top
    if m.total then
      panel(f, m.total, 2, y, width, h, levelOf(m.total, m.alerts), function() actions.open("") end)
      y = y + h + 1
    end
    local pw = (width - (cols - 1) * 3) // cols
    for i, r in ipairs(m.lscs) do
      local col = (i - 1) % cols
      local py = y + ((i - 1) // cols) * (h + 1)
      if py + h - 1 > bottom then
        f:text(2, bottom + 1, ("+%d more LSCs"):format(#m.lscs - i + 1), C.dim)
        break
      end
      panel(f, r, 2 + col * (pw + 3), py, pw, h, levelOf(r, m.alerts), function() actions.open(r.address) end)
    end
  end

  if powerRows > 0 then powerSection(f, m, secs, titled, L, 2, powerTop, width, actions) end
  main.alerts(f, m, 2, alertTop, width, f.h - 1)
end

return main
