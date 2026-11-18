--[[ lumen.setup.screen: lumen-setup's touchscreen editor (a GPU and screen of 80x25 or more).

  Screen.available(component) -> true | nil, why
  Screen.run(env) -> "text" | nil      env = { component, event, computer?, cfgPath, shrcPath }; "text" when the
                                       user asked for the text setup instead

  Tabs: LSCS (a name for each), SOURCES (reactors and GT machines: show it, its name, always on), SWITCHES (a
  row per switch; tap one to edit it: name, group or marks, redstone block and side or GT machine, the LSC it
  follows, its source, its heat trip, its fault input; ▲ ▼ to move it, + NEW, COPY for the next one, DELETE;
  PAIR), GROUPS (name, rotate, the LSC it follows, members, steps; + NEW, ADD EVERY SWITCH, DELETE), GENERAL
  (alerts, LENS, start on boot). Long choices (a component, an LSC, a source, a group) open a list to tap. READ
  shows which sides of a switch's redstone blocks have a signal coming in, to tell blocks apart. PAIR finds
  which reactor each switch runs by running them one at a time (lumen.setup.pair), after explaining and a
  START; APPLY makes them the switches' sources. SAVE shows the changes and warnings, then writes lumen.cfg
  (keeping lumen.cfg.bak) and .shrc. Keys: typing goes to the field being edited (Enter done, Esc cancels);
  otherwise Up/Down pick a row and Left/Right switch tabs. The edits live in lumen.setup.editor.
]]

local unicode = require("unicode")
local Gui     = require("lumen.gui")
local frame   = require("lumen.frame")
local VERSION = require("lumen.version")
local Editor  = require("lumen.setup.editor")
local files   = require("lumen.setup.files")
local scan    = require("lumen.setup.scan")
local Pair    = require("lumen.setup.pair")
local config  = require("lumen.config")

local Screen = {}

local MIN_W, MIN_H = 80, 25
local KEY = { enter = 28, back = 14, esc = 1, up = 200, down = 208, left = 203, right = 205 }
local TABS = {
  { id = "lscs", title = "LSCS" }, { id = "sources", title = "SOURCES" },
  { id = "switches", title = "SWITCHES" }, { id = "groups", title = "GROUPS" }, { id = "general", title = "GENERAL" },
}
local SIDES = scan.SIDES
local C = Gui.C
local fit = Gui.fit

function Screen.available(component)
  if not (component.isAvailable("gpu") and component.isAvailable("screen")) then return nil, "no GPU and screen" end
  local w, h = component.gpu.maxResolution()
  if w < MIN_W or h < MIN_H then return nil, ("the screen is %dx%d; the editor needs %dx%d"):format(w, h, MIN_W, MIN_H) end
  return true
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function whole(text, lo, hi)
  local n = tonumber(text)
  if n and n == math.floor(n) and n >= lo and n <= hi then return math.floor(n) end
end

function Screen.run(env)
  local component, event = env.component, env.event
  local uptime = env.computer and env.computer.uptime or os.clock
  -- The screen's shape, like lumen's "fit"; the largest when that's too small for the editor.
  local W, H = Gui.size(component, "fit")
  if W < MIN_W or H < MIN_H then W, H = component.gpu.maxResolution() end
  local ui = Gui.new(component.gpu, W, H)
  local LIST_TOP, SEP = 4, H - 11
  local LIST_BOTTOM, DETAIL, MSG, FOOT = SEP - 1, H - 10, H - 1, H

  local ed = Editor.new(files.loadOld(env.cfgPath), scan.snapshot(component))
  local S = {
    tab = "lscs", sel = {}, scroll = {}, view = "edit", running = true,
    focus = nil,            -- { id, text, apply(text) -> err? } while typing
    boot = files.bootPresent(env.shrcPath),
    pick = nil,             -- { what, i, title, scroll } on the pick view
    inputs = {},            -- redstone address -> what READ found
    msg = nil, msgOk = true, confirm = nil, result = nil,
    pair = nil,             -- lumen.setup.pair while PAIR runs (or has run)
  }
  local painted, hits = {}, {}

  local function flash(text, ok) S.msg, S.msgOk = text, ok ~= false end
  local function report(ok, why) if not ok and why then flash(why, false) end end
  local function shrc() return files.shrcText(env.shrcPath, S.boot) end
  local function dirty() return #ed.changes() > 0 or shrc() ~= nil end

  local function commitFocus()
    local f = S.focus
    if not f then return end
    S.focus = nil
    local err = f.apply(trim(f.text))
    if err then flash(err, false) end
  end

  ---------------------------------------------------------------- rows of each list tab
  local function rows()
    if S.tab == "lscs" then
      local out = {}
      for _, r in ipairs(ed.lscRows()) do out[#out + 1] = { key = r.key, r = r } end
      return out
    elseif S.tab == "sources" then
      local out = {}
      for _, r in ipairs(ed.sourceRows()) do out[#out + 1] = { key = r.key, r = r } end
      return out
    elseif S.tab == "switches" then
      local out = {}
      for i, sw in ipairs(ed.c.control) do out[#out + 1] = { key = sw.name, i = i, sw = sw } end
      return out
    elseif S.tab == "groups" then
      local out = {}
      for gi, g in ipairs(ed.c.groups) do out[#out + 1] = { key = g.name, gi = gi, g = g } end
      return out
    end
    return {}
  end
  local function selected()
    for _, row in ipairs(rows()) do if row.key == S.sel[S.tab] then return row end end
  end
  local function listHeight() return LIST_BOTTOM - LIST_TOP + 1 end
  local function reveal(at)
    local scroll, height = S.scroll[S.tab] or 0, listHeight()
    if at <= scroll then scroll = at - 1 elseif at > scroll + height then scroll = at - height end
    S.scroll[S.tab] = math.max(0, scroll)
  end
  local function moveSel(d)
    local list = rows()
    if #list == 0 then return end
    local at = 0
    for i, row in ipairs(list) do if row.key == S.sel[S.tab] then at = i end end
    at = math.max(1, math.min(#list, at + d))
    S.sel[S.tab] = list[at].key
    reveal(at)
  end
  local function scrollBy(d)
    local maxScroll = math.max(0, #rows() - listHeight())
    S.scroll[S.tab] = math.max(0, math.min(maxScroll, (S.scroll[S.tab] or 0) + d))
  end
  local function selectSwitch(i)
    local sw = ed.c.control[i]
    if sw then S.sel.switches = sw.name; reveal(i) end
  end

  ---------------------------------------------------------------- widgets
  local f   -- the frame being built
  local function say(x, y, text, fg, bg) f:text(x, y, text, fg, bg) end   -- cut at the edge (frame does it)
  local function button(x, y, label, fn, on, color)
    local s = " " .. label .. " "
    f:text(x, y, s, C.text, color or (on and C.btnOn or C.btn))
    local x2 = x + Gui.len(s) - 1
    f:hit(x, y, x2, y, function() commitFocus(); fn() end)
    return x2 + 2
  end
  -- A text field: tap it to type. apply(text) -> error text | nil.
  local function field(x, y, w, id, value, apply)
    local active = S.focus and S.focus.id == id
    local shown = active and (S.focus.text .. "_") or tostring(value == nil and "" or value)
    if active and unicode.len(shown) > w then shown = unicode.sub(shown, -w) end
    f:text(x, y, fit(shown, w), active and C.accent or C.text, C.field)
    f:hit(x, y, x + w - 1, y, function()
      commitFocus()
      S.focus = { id = id, text = tostring(value == nil and "" or value), apply = apply }
    end)
    return x + w + 1
  end
  local function toggle(x, y, label, on, fn) return button(x, y, label, function() fn(not on) end, on) end
  local function sideButtons(x, y, current, fn)
    local name = Editor.sideName(current)
    for _, s in ipairs(SIDES) do x = button(x, y, s, function() fn(s) end, s == name) end
    return x
  end
  local function openPick(what, i, title)
    S.pick = { what = what, i = i, title = title, scroll = 0 }
    S.view = "pick"
  end

  ---------------------------------------------------------------- list tabs
  local function mark(ok, used)
    if not ok then return "!", C.bad end
    if used then return "●", C.good end
    return "·", C.dim
  end

  local function swOk(sw)
    local function has(list, prefix, fieldName)
      for _, x in ipairs(list or {}) do
        local a = fieldName and x[fieldName] or x
        if prefix and a:sub(1, #prefix) == prefix then return true end
      end
    end
    local ok = sw.redstone and has(ed.snap.redstone, sw.redstone) or (sw.machine and has(ed.snap.gts, sw.machine, "address"))
    if sw.fault and not has(ed.snap.redstone, sw.fault.redstone) then ok = false end
    return ok and true or false
  end

  local function faultShort(sw)
    local fl = sw.fault
    if not fl then return "none", C.dim end
    local s = Editor.sideName(fl.side)
    if fl.redstone ~= sw.redstone then s = fl.redstone:sub(1, 4) .. " " .. s end
    if fl.latch then s = s .. ", latch" end
    if fl.stop == false then s = s .. ", alert" end
    return s, C.warn
  end

  local COLS = {
    lscs = { { 4, "ADDRESS" }, { 14, "NAME" }, { 40, "NOW" } },
    sources = { { 4, "ADDRESS" }, { 14, "WHAT" }, { 42, "NAME" }, { 64, "" } },
    switches = { { 4, "NAME" }, { 23, "RUN BY" }, { 47, "RUNS" }, { 56, "SOURCE" }, { 71, "FAULT" } },
    groups = { { 4, "NAME" }, { 23, "MEMBERS" }, { 33, "STEPS" } },
  }

  local function drawRow(row, y, bg)
    if S.tab == "lscs" then
      local r = row.r
      local m, mc = mark(r.found ~= nil, r.name ~= nil)
      f:text(2, y, m, mc, bg)
      f:text(4, y, fit(r.key, 9), C.text, bg)
      f:text(14, y, fit(r.name or ("LSC " .. r.key:sub(1, 4) .. " (no name)"), 25), r.name and C.text or C.dim, bg)
      local now = not r.found and "not found - still in lumen.cfg"
        or (r.found.ok and r.found.fill and ("%.1f%% full"):format(r.found.fill * 100) or "can't be read")
      f:text(40, y, fit(now, W - 40), r.found and C.dim or C.bad, bg)
    elseif S.tab == "sources" then
      local r = row.r
      local m, mc = mark(r.found, r.entry ~= nil)
      f:text(2, y, m, mc, bg)
      f:text(4, y, fit(r.key, 9), C.text, bg)
      f:text(14, y, fit(r.label, 27), r.found and C.text or C.bad, bg)
      f:text(42, y, fit(r.entry and r.entry.name or "not shown", 21), r.entry and C.text or C.dim, bg)
      f:text(64, y, fit(r.entry and r.entry.alwaysOn and "always on" or "", W - 64), C.info, bg)
    elseif S.tab == "groups" then
      local n = #ed.members(row.gi)
      local m, mc = mark(n > 0, true)
      f:text(2, y, m, mc, bg)
      f:text(4, y, fit(row.g.name, 18), C.text, bg)
      f:text(23, y, tostring(n), n > 0 and C.text or C.warn, bg)
      f:text(33, y, fit(ed.describeGroup(row.g), W - 33), C.dim, bg)
    else
      local sw = row.sw
      local m, mc = mark(swOk(sw), true)
      f:text(2, y, m, mc, bg)
      f:text(4, y, fit(sw.name, 18), C.text, bg)
      local by = sw.redstone and ("redstone %s %s"):format(sw.redstone, Editor.sideName(sw.side)) or ("GT " .. tostring(sw.machine))
      f:text(23, y, fit(by, 23), C.text, bg)
      f:text(47, y, fit(sw.group or (sw.always and "always") or ("%g-%g%%"):format(sw.onBelow or 0, sw.offAbove or 0), 8),
        (sw.group or sw.always) and C.info or C.text, bg)
      f:text(56, y, fit(sw.source or "none", 14), sw.source and C.text or C.dim, bg)
      local ft, fc = faultShort(sw)
      f:text(71, y, fit(ft, W - 71), fc, bg)
    end
  end

  local HINT = {
    lscs = "No LSC found: put an adapter against an LSC's controller (touching this computer, or cabled to it).",
    sources = "No reactor or GT machine found: put an adapter against a generator's controller or a reactor.",
    switches = "No switches yet: + NEW makes one. A switch turns generators on below one fill and off above another.",
    groups = "No groups yet: + NEW makes one. A group runs as many of its switches as the fill needs.",
  }

  local function drawList()
    for _, col in ipairs(COLS[S.tab]) do f:text(col[1], 3, col[2], C.dim) end
    local list = rows()
    local height, scroll = listHeight(), S.scroll[S.tab] or 0
    if #list == 0 then say(3, LIST_TOP + 1, HINT[S.tab], C.dim) end
    for i = 1, height do
      local row, y = list[scroll + i], LIST_TOP + i - 1
      if row then
        local bg = row.key == S.sel[S.tab] and C.sel or C.bg
        f:rowBg(y, bg)
        drawRow(row, y, bg)
        f:hit(1, y, W, y, function() commitFocus(); S.sel[S.tab] = row.key end)
      end
    end
  end

  ---------------------------------------------------------------- details
  local P = C.panel

  local function lscDetail(row)
    local r, y = row.r, DETAIL
    local now = r.found and (r.found.ok and r.found.fill and (", %.1f%% full"):format(r.found.fill * 100) or ", can't be read") or ""
    say(3, y, "LSC " .. r.address .. now, C.accent, P)
    if not r.found then
      say(3, y + 1, "Not found: check its adapter and RESCAN, or DROP its name.", C.bad, P)
      button(3, y + 2, "DROP", function() ed.dropLsc(r.key); S.sel.lscs = nil end, false, C.bad)
      return
    end
    f:text(3, y + 2, "Name", C.dim, P)
    local x = field(12, y + 2, 24, "lscname", r.name or "", function(text) ed.nameLsc(r.key, text) end)
    say(x, y + 2, "on screen, in alerts and in LENS; blank = LSC " .. r.key:sub(1, 4), C.dim, P)
  end

  local function sourceDetail(row)
    local r, y = row.r, DETAIL
    local e = r.entry
    say(3, y, (r.kind == "reactor" and "IC2 reactor " or (r.kind == "gt" and (r.label .. " ") or "Source ")) .. r.key, C.accent, P)
    if not r.found then
      say(3, y + 1, "Not found: check its adapter and RESCAN, or DROP it.", C.bad, P)
      button(3, y + 2, "DROP", function() ed.dropSource(r.key); S.sel.sources = nil end, false, C.bad)
      return
    end
    f:text(3, y + 2, "Show", C.dim, P)
    if r.kind == "reactor" then
      say(12, y + 2, "always, with its heat and EU/t", C.dim, P)
    else
      local x = toggle(12, y + 2, "YES", e ~= nil, function() report(ed.showSource(r.key, true)) end)
      toggle(x, y + 2, "NO", e == nil, function() report(ed.showSource(r.key, false)) end)
    end
    if not e then return end
    f:text(3, y + 3, "Name", C.dim, P)
    local x = field(12, y + 3, 20, "srcname", e.name, function(text)
      local ok, why = ed.setSource(r.key, "name", text)
      if not ok then return why end
    end)
    say(x, y + 3, "on screen, in alerts and in LENS", C.dim, P)
    f:text(3, y + 4, "Always on", C.dim, P)
    x = toggle(14, y + 4, "YES", e.alwaysOn == true, function() ed.setSource(r.key, "alwaysOn", true) end)
    x = toggle(x, y + 4, "NO", not e.alwaysOn, function() ed.setSource(r.key, "alwaysOn", false) end)
    say(x, y + 4, "warn when it hasn't run for 5 minutes", C.dim, P)
  end

  local function inputsText(address)
    local got = S.inputs[address]
    if got == nil then return nil end
    if type(got) == "string" then return address .. ": can't be read (" .. got .. ")" end
    if #got == 0 then return address .. ": no signal in" end
    local parts = {}
    for _, s in ipairs(got) do parts[#parts + 1] = s.side .. " " .. s.level end
    return address .. ": signal in " .. table.concat(parts, ", ")
  end

  local function readInputs(sw)
    local done = {}
    for _, a in ipairs({ sw.redstone, sw.fault and sw.fault.redstone }) do
      if a and not done[a] then
        done[a] = true
        local full
        for _, r in ipairs(ed.snap.redstone) do if r:sub(1, #a) == a then full = r end end
        local got, err = nil, "not found"
        if full then got, err = scan.inputs(component, full) end
        S.inputs[a] = got or err
      end
    end
  end

  local function inputsSummary(sw)
    local parts = {}
    for _, a in ipairs({ sw.redstone, sw.fault and sw.fault.redstone }) do
      local t = a and inputsText(a)
      if t and (#parts == 0 or a ~= sw.redstone) then parts[#parts + 1] = t end
    end
    return #parts > 0 and table.concat(parts, "   ") or "nothing read"
  end

  local function switchDetail(row)
    local i, sw, y = row.i, row.sw, DETAIL
    local set = function(k, v) report(ed.setSwitch(i, k, v)) end
    say(3, y, "Switch " .. sw.name, C.accent, P)
    local bx = W - 35
    bx = button(bx, y, "▲", function() local j = ed.moveSwitch(i, -1); if j then selectSwitch(j) end end)
    bx = button(bx, y, "▼", function() local j = ed.moveSwitch(i, 1); if j then selectSwitch(j) end end)
    if sw.redstone or sw.fault then
      bx = button(bx, y, "READ", function() readInputs(sw); flash(inputsSummary(sw)) end)
    end
    bx = button(bx, y, "COPY", function()
      local at, why = ed.copySwitch(i)
      if at then selectSwitch(at); flash("Copied: pick its redstone block and source if they're not right.") else flash(why, false) end
    end)
    button(bx, y, "DELETE", function()
      if S.confirm == "delete" then ed.deleteSwitch(i); S.sel.switches = nil; S.confirm = nil
      else S.confirm = "delete"; flash("Tap DELETE again to delete " .. sw.name, false) end
    end, false, S.confirm == "delete" and C.bad or nil)

    y = y + 1
    f:text(3, y, "Name", C.dim, P)
    local x = field(12, y, 16, "swname", sw.name, function(text)
      local ok, why = ed.setSwitch(i, "name", text)
      if ok then S.sel.switches = text else return why end
    end)
    f:text(x, y, "Runs", C.dim, P)
    x = button(x + 5, y, (sw.group or (sw.always and "always") or "by fill") .. " ▸", function()
      openPick("runs", i, "How " .. sw.name .. " runs: by the fill, always, or in a group")
    end)
    if sw.group then
      say(x, y, "its group's steps say when it runs", C.dim, P)
    elseif sw.always then
      say(x, y, "ON / OFF on the screen; faults and heat trips still stop it", C.dim, P)
    else
      f:text(x, y, "on below", C.dim, P)
      x = field(x + 9, y, 3, "onbelow", sw.onBelow, function(text)
        local ok, why = ed.setSwitch(i, "onBelow", whole(text, 0, 100) or -1)
        if not ok then return why end
      end)
      f:text(x - 1, y, "% off above", C.dim, P)
      x = field(x + 11, y, 3, "offabove", sw.offAbove, function(text)
        local ok, why = ed.setSwitch(i, "offAbove", whole(text, 0, 100) or -1)
        if not ok then return why end
      end)
      say(x - 1, y, "%", C.dim, P)
    end

    y = y + 1
    f:text(3, y, "Run by", C.dim, P)
    x = toggle(12, y, "REDSTONE", sw.redstone ~= nil, function() set("kind", "redstone") end)
    x = toggle(x, y, "GT MACHINE", sw.machine ~= nil, function() set("kind", "machine") end)
    if sw.redstone then
      x = button(x + 1, y, "redstone " .. sw.redstone .. " ▸", function()
        openPick("redstone", i, "The Redstone I/O block or card " .. sw.name .. "'s signal goes out of")
      end)
      say(x, y, "READ: which sides have a signal in", C.dim, P)
    else
      local label = tostring(sw.machine)
      for _, g in ipairs(ed.snap.gts) do if g.address:sub(1, #label) == label then label = g.name:gsub("^.*%.", "") .. " " .. label end end
      button(x + 1, y, label .. " ▸", function() openPick("machine", i, "The GT machine " .. sw.name .. " switches") end)
    end

    y = y + 1
    if sw.redstone then
      f:text(3, y, "Side", C.dim, P)
      x = sideButtons(12, y, sw.side, function(s2) set("side", s2) end)
      toggle(x, y, "SIGNAL = STOP", sw.invert == true, function(v) set("invert", v) end)
    else
      say(12, y, "its work switch, the same as a soft mallet on its controller", C.dim, P)
    end

    y = y + 1
    f:text(3, y, "Follows", C.dim, P)
    if sw.group then say(12, y, "its group's LSC", C.dim, P); x = 28
    elseif sw.always then say(12, y, "no fill", C.dim, P); x = 28
    else
      x = button(12, y, (sw.lsc or "all LSCs") .. " ▸", function() openPick("lsc", i, "The LSC " .. sw.name .. " follows") end)
    end
    f:text(math.max(x, 36), y, "Source", C.dim, P)
    button(math.max(x, 36) + 7, y, (sw.source or "none") .. " ▸", function()
      openPick("source", i, "The source " .. sw.name .. " switches (LUMEN warns when it doesn't follow)")
    end)

    y = y + 1
    f:text(3, y, "Heat trip", C.dim, P)
    local tripOn = sw.heatTrip ~= nil or sw.heatRise ~= nil
    x = toggle(13, y, "OFF", not tripOn, function() set("heatTrip", nil); set("heatRise", nil) end)
    x = toggle(x, y, "ON", tripOn, function() if not tripOn then set("heatTrip", 90) end end)
    if tripOn then
      f:text(x, y, "at", C.dim, P)
      x = field(x + 3, y, 3, "heattrip", sw.heatTrip, function(text)
        if text == "" then set("heatTrip", nil); return end
        local ok, why = ed.setSwitch(i, "heatTrip", whole(text, 1, 100) or -1)
        if not ok then return why end
      end)
      f:text(x - 1, y, "% heat, or rising", C.dim, P)
      x = field(x + 17, y, 3, "heatrise", sw.heatRise, function(text)
        if text == "" then set("heatRise", nil); return end
        local ok, why = ed.setSwitch(i, "heatRise", whole(text, 1, 100) or -1)
        if not ok then return why end
      end)
      say(x - 1, y, "% a minute: off until RESET", C.dim, P)
    else
      say(x, y, "switch off and latch when its reactor runs too hot (set per reactor)", C.dim, P)
    end

    y = y + 1
    local fl = sw.fault
    f:text(3, y, "Fault", C.dim, P)
    x = toggle(12, y, "OFF", fl == nil, function() ed.setFault(i, "on", false) end)
    x = toggle(x, y, "ON", fl ~= nil, function() report(ed.setFault(i, "on", true)) end)
    if fl then
      f:text(x, y, "comes into", C.dim, P)
      x = button(x + 11, y, "redstone " .. fl.redstone .. " ▸", function()
        openPick("faultRedstone", i, "The Redstone I/O block or card " .. sw.name .. "'s fault signal comes into")
      end)
      say(x, y, "a redstone line that means trouble", C.dim, P)
      y = y + 1
      f:text(5, y, "side", C.dim, P)
      sideButtons(12, y, fl.side, function(s2) report(ed.setFault(i, "side", s2)) end)
      y = y + 1
      f:text(5, y, "it's", C.dim, P)
      x = toggle(12, y, "OK SIGNAL", fl.invert == true, function(v) ed.setFault(i, "invert", v) end)
      x = toggle(x, y, "LATCH", fl.latch == true, function(v) ed.setFault(i, "latch", v) end)
      x = toggle(x, y, "STOP", fl.stop ~= false, function(v) ed.setFault(i, "stop", v) end)
      say(x, y, (fl.invert and "trouble when it goes" or "trouble while it's on") .. (fl.latch and "; until RESET" or "")
        .. (fl.stop ~= false and "; switches off" or "; alert only"), C.dim, P)
    else
      say(x, y, "optional: a redstone line from what it runs that means trouble (SFM's error output...)", C.dim, P)
    end
  end

  local function groupDetail(row)
    local gi, g, y = row.gi, row.g, DETAIL
    say(3, y, "Group " .. g.name, C.accent, P)
    local bx = W - 29
    bx = button(bx, y, "ADD EVERY SWITCH", function()
      local n = ed.joinAll(gi)
      flash(n == 0 and "Every switch is in a group already." or (n .. " switches joined " .. g.name .. "."))
    end)
    button(bx, y, "DELETE", function()
      if S.confirm == "gdelete" then ed.deleteGroup(gi); S.sel.groups = nil; S.confirm = nil
      else S.confirm = "gdelete"; flash("Tap DELETE again to delete " .. g.name .. " (its switches stay, with marks)", false) end
    end, false, S.confirm == "gdelete" and C.bad or nil)

    y = y + 1
    f:text(3, y, "Name", C.dim, P)
    local x = field(12, y, 16, "gname", g.name, function(text)
      local ok, why = ed.setGroup(gi, "name", text)
      if ok then S.sel.groups = text else return why end
    end)
    f:text(x, y, "Rotate", C.dim, P)
    x = toggle(x + 7, y, "ON", g.rotate ~= false, function() ed.setGroup(gi, "rotate", true) end)
    x = toggle(x, y, "OFF", g.rotate == false, function() ed.setGroup(gi, "rotate", false) end)
    f:text(x, y, "Follows", C.dim, P)
    button(x + 8, y, (g.lsc or "all LSCs") .. " ▸", function() openPick("groupLsc", gi, "The LSC " .. g.name .. " follows") end)

    y = y + 1
    local mem, names = ed.members(gi), {}
    for _, i in ipairs(mem) do names[#names + 1] = ed.c.control[i].name end
    f:text(3, y, "Members", C.dim, P)
    say(12, y, #mem == 0 and "none yet: set a switch's Group, or ADD EVERY SWITCH" or (#mem .. ": " .. table.concat(names, ", ")),
      #mem == 0 and C.warn or C.text, P)

    local cum = 0
    for k, st in ipairs(g.steps) do
      if k > 4 then say(3, y + 1, ("+%d more steps in lumen.cfg"):format(#g.steps - 4), C.dim, P); break end
      y = y + 1
      cum = cum + st.run
      f:text(3, y, "Step " .. k, C.dim, P)
      f:text(11, y, "below", C.dim, P)
      x = field(17, y, 3, "sb" .. k, st.onBelow, function(text)
        local ok, why = ed.setStep(gi, k, "onBelow", whole(text, 0, 100) or -1)
        if not ok then return why end
      end)
      f:text(x - 1, y, "% run", C.dim, P)
      x = field(x + 5, y, 3, "sr" .. k, st.run, function(text)
        local ok, why = ed.setStep(gi, k, "run", whole(text, 1, 999) or -1)
        if not ok then return why end
      end)
      f:text(x - 1, y, " more, off above", C.dim, P)
      x = field(x + 16, y, 3, "so" .. k, st.offAbove, function(text)
        local ok, why = ed.setStep(gi, k, "offAbove", whole(text, 0, 100) or -1)
        if not ok then return why end
      end)
      f:text(x - 1, y, "%", C.dim, P)
      x = button(x + 1, y, "REMOVE", function() report(ed.dropStep(gi, k)) end)
      say(x, y, ("= %d on"):format(cum), C.dim, P)
    end
    y = y + 1
    if #g.steps < 4 then
      local x2 = button(3, y, "+ STEP", function() ed.addStep(gi) end)
      say(x2, y, "each step runs more below its mark, and lets them go above its off mark", C.dim, P)
    end
  end

  ---------------------------------------------------------------- general
  local function drawGeneral()
    local c = ed.c
    local step = listHeight() >= 15 and 2 or 1
    local y = LIST_TOP
    local function label(text) f:text(3, y, text, C.dim) end
    local function num(x, w, id, key, lo, hi, what)
      local v = c[key]
      if v == nil then v = config.DEFAULTS[key] end   -- a file from before the setting existed
      return field(x, y, w, id, v, function(text)
        local n = whole(text, lo, hi)
        if not n then return ("%s must be a whole number from %d to %d"):format(what, lo, hi) end
        ed.set(key, n)
      end)
    end
    local x
    label("Fill")
    f:text(20, y, "warn below", C.dim)
    x = num(31, 4, "lowfill", "lowFill", 1, 100, "warn below")
    f:text(x - 1, y, "%   bad below", C.dim)
    x = num(x + 13, 4, "critfill", "criticalFill", 0, 100, "bad below")
    say(x - 1, y, "%", C.dim)
    y = y + step
    label("Draining")
    f:text(20, y, "warn within", C.dim)
    x = num(32, 4, "drainwarn", "drainWarnHours", 1, 1000, "warn within")
    f:text(x - 1, y, "h   bad within", C.dim)
    x = num(x + 14, 4, "drainbad", "drainBadHours", 0, 1000, "bad within")
    say(x - 1, y, "h  empty", C.dim)
    y = y + step
    label("Input drop")
    x = toggle(20, y, "OFF", c.inputDrop == nil, function() ed.set("inputDrop", nil) end)
    x = toggle(x, y, "ON", c.inputDrop ~= nil, function() ed.set("inputDrop", c.inputDrop or 50) end)
    if c.inputDrop then
      x = num(x, 4, "inputdrop", "inputDrop", 1, 100, "the input drop")
      say(x - 1, y, "% below the hour's (off if generators cycle by themselves)", C.dim)
    else
      say(x, y, "warn when input falls well below the hour's", C.dim)
    end
    y = y + step
    label("Reactor heat")
    f:text(20, y, "warn at", C.dim)
    x = num(28, 4, "heatwarn", "heatWarn", 0, 100, "warn at")
    f:text(x - 1, y, "%   bad at", C.dim)
    x = num(x + 10, 4, "heatbad", "heatBad", 0, 100, "bad at")
    say(x - 1, y, "% of its max (MOX and breeders run hot: set these per design)", C.dim)
    y = y + step
    label("Beep")
    x = toggle(20, y, "ON", c.beep ~= false, function() ed.set("beep", true) end)
    x = toggle(x, y, "OFF", c.beep == false, function() ed.set("beep", false) end)
    say(x, y, "once when a bad alert appears", C.dim)
    y = y + step
    label("Big mode")
    local after = c.glanceAfter == nil and 300 or c.glanceAfter
    x = toggle(20, y, "ON", after > 0, function() if after == 0 then ed.set("glanceAfter", 300) end end)
    x = toggle(x, y, "OFF", after == 0, function() ed.set("glanceAfter", 0) end)
    if after > 0 then
      f:text(x, y, "after", C.dim)
      x = field(x + 6, y, 3, "glanceafter", math.max(1, math.floor(after / 60 + 0.5)), function(text)
        local n = whole(text, 1, 600)
        if not n then return "big mode's wait must be a whole number of minutes, 1-600" end
        ed.set("glanceAfter", n * 60)
      end)
      f:text(x - 1, y, " min idle,", C.dim)
      x = x + 10
    else
      f:text(x, y, "only with BIG on the screen;", C.dim)
      x = x + 29
    end
    f:text(x, y, "x", C.dim)
    x = num(x + 2, 2, "glancescale", "glanceScale", 2, 6, "big mode's size")
    say(x - 1, y, " bigger", C.dim)
    y = y + step
    label("Wake it")
    local kinds = ed.snap.presence or {}
    if #kinds == 0 then
      say(20, y, "by tapping (a radar, entity detector or motion sensor wakes it as you walk up)", C.dim)
    else
      local found = table.concat(kinds, ", ") .. ": within"
      say(20, y, found, C.text)
      x = 20 + Gui.len(found)
      x = num(x + 1, 2, "wakerange", "wakeRange", 1, 8, "the wake range")
      f:text(x - 1, y, " blocks, only", C.dim)
      x = field(x + 13, y, 16, "wakeplayers", table.concat(c.wakePlayers or {}, ", "), function(text)
        local names = {}
        for n in text:gmatch("[^,]+") do
          n = trim(n)
          if n ~= "" then names[#names + 1] = n end
        end
        ed.set("wakePlayers", #names > 0 and names or nil)
      end)
      say(x, y, "(blank: anyone); or a tap", C.dim)
    end
    y = y + step
    label("LENS")
    x = toggle(20, y, "OFF", c.lensPort == nil, function() ed.set("lensPort", nil) end)
    x = toggle(x, y, "ON", c.lensPort ~= nil, function() ed.set("lensPort", c.lensPort or 4243) end)
    if c.lensPort then
      f:text(x, y, "port", C.dim)
      x = num(x + 5, 6, "lensport", "lensPort", 1, 65535, "the LENS port")
      f:text(x, y, "name", C.dim)
      x = field(x + 5, y, 12, "lensnode", c.lensNode or "lumen", function(text)
        if text == "" then return "LENS needs a name for this computer" end
        ed.set("lensNode", text)
      end)
      f:text(x, y, "token", C.dim)
      field(x + 6, y, 10, "lenstoken", c.lensToken or "", function(text) ed.set("lensToken", text ~= "" and text or nil) end)
    else
      say(x, y, ed.snap.modem and "report to a LENS hub" or "needs a network card", C.dim)
    end
    y = y + step
    label("Start on boot")
    x = toggle(20, y, "ON", S.boot, function() S.boot = true end)
    toggle(x, y, "OFF", not S.boot, function() S.boot = false end)
  end

  local function generalDetail()
    local warnings = ed.warnings()
    local ok, why = ed.check()
    if not ok then table.insert(warnings, 1, "can't save: " .. why) end
    f:text(3, DETAIL, #warnings == 0 and "No warnings." or "Warnings", #warnings == 0 and C.good or C.warn, P)
    for k = 1, math.min(#warnings, MSG - DETAIL - 2) do say(3, DETAIL + k, warnings[k], C.warn, P) end
  end

  ---------------------------------------------------------------- views
  local function header(title, color)
    f:rowBg(1, P)
    f:text(2, 1, title, color or C.accent, P)
  end

  local function drawEdit()
    header("LUMEN setup " .. VERSION)
    say(16 + Gui.len(VERSION), 1, fit(env.cfgPath, math.max(0, W - 34 - Gui.len(VERSION))), C.dim, P)
    if dirty() then f:text(W - 16, 1, "unsaved changes", C.warn, P) end
    local x = 2
    for _, t in ipairs(TABS) do
      local label = t.title
      if t.id == "lscs" then label = label .. " " .. #ed.lscRows()
      elseif t.id == "sources" then label = label .. " " .. #ed.c.sources
      elseif t.id == "switches" then label = label .. " " .. #ed.c.control
      elseif t.id == "groups" then label = label .. " " .. #ed.c.groups end
      x = button(x, 2, label, function() S.tab = t.id end, S.tab == t.id)
    end
    if S.tab == "general" then drawGeneral() else drawList() end
    for y = SEP, MSG - 1 do f:rowBg(y, P) end
    f:text(1, SEP, string.rep("─", W), C.line, P)
    local row = selected()
    if S.tab == "general" then generalDetail()
    elseif not row then say(3, DETAIL, "Tap a row to change it.", C.dim, P)
    elseif S.tab == "lscs" then lscDetail(row)
    elseif S.tab == "sources" then sourceDetail(row)
    elseif S.tab == "groups" then groupDetail(row)
    else switchDetail(row) end
    if S.msg then say(3, MSG, S.msg, S.msgOk and C.good or C.bad) end
    x = button(2, FOOT, "SAVE", function() S.view = "review" end, dirty())
    x = button(x, FOOT, "RESCAN", function()
      ed.rescan(scan.snapshot(component)); S.inputs = {}; flash("Rescanned the attached components.")
    end)
    x = button(x, FOOT, "TEXT SETUP", function()
      if dirty() and S.confirm ~= "text" then
        S.confirm = "text"; flash("Unsaved changes: tap TEXT SETUP again to throw them away", false); return
      end
      S.result, S.running = "text", false
    end)
    x = button(x, FOOT, "QUIT", function()
      if dirty() and S.confirm ~= "quit" then
        S.confirm = "quit"; flash("Unsaved changes: tap QUIT again to throw them away", false); return
      end
      S.running = false
    end, false, S.confirm == "quit" and C.bad or nil)
    if S.tab == "switches" then
      x = button(x + 2, FOOT, "+ NEW", function()
        local at, why = ed.addSwitch()
        if at then selectSwitch(at) else flash(why, false) end
      end)
      button(x, FOOT, "PAIR", function() S.pair = nil; S.view = "pair" end)
    elseif S.tab == "groups" then
      button(x + 2, FOOT, "+ NEW", function()
        local gi = ed.addGroup()
        S.sel.groups = ed.c.groups[gi].name
      end)
    end
    local list = S.tab ~= "general" and rows() or {}
    if #list > listHeight() then
      local scroll = S.scroll[S.tab] or 0
      local count = ("%d-%d of %d"):format(scroll + 1, math.min(#list, scroll + listHeight()), #list)
      f:text(W - 10 - Gui.len(count), FOOT, count, C.dim)
      x = button(W - 9, FOOT, "▲", function() scrollBy(-listHeight() + 1) end)
      button(x, FOOT, "▼", function() scrollBy(listHeight() - 1) end)
    end
  end

  local function drawPick()
    local p = S.pick
    header(p.title)
    local list = ed.choices(p.what, p.i)
    local sw = ed.c.control[p.i] or {}
    local current = p.what == "redstone" and sw.redstone or p.what == "machine" and sw.machine or p.what == "lsc" and sw.lsc
      or p.what == "source" and sw.source or p.what == "group" and sw.group
      or p.what == "runs" and (sw.group or (sw.always and "always") or "marks")
      or p.what == "groupLsc" and (ed.c.groups[p.i] or {}).lsc
      or p.what == "faultRedstone" and (sw.fault and sw.fault.redstone)
    local top, height = 3, H - 4
    for k = 1, height do
      local ch, y = list[p.scroll + k], top + k - 1
      if ch then
        local on = ch.value == current
        local bg = on and C.sel or C.bg
        f:rowBg(y, bg)
        f:text(2, y, on and "●" or "·", on and C.good or C.dim, bg)
        f:text(4, y, fit(ch.label, 30), C.text, bg)
        say(36, y, ch.note or "", C.dim, bg)
        f:hit(1, y, W, y, function()
          local ok, why
          if p.what == "faultRedstone" then ok, why = ed.setFault(p.i, "redstone", ch.value)
          elseif p.what == "groupLsc" then ok, why = ed.setGroup(p.i, "lsc", ch.value)
          else ok, why = ed.setSwitch(p.i, p.what, ch.value) end
          report(ok, why)
          S.view = "edit"
        end)
      end
    end
    local x = button(2, FOOT, "BACK", function() S.view = "edit" end)
    if #list > height then
      x = button(x, FOOT, "▲", function() p.scroll = math.max(0, p.scroll - height + 1) end)
      button(x, FOOT, "▼", function() p.scroll = math.min(#list - height, p.scroll + height - 1) end)
    end
  end

  local function lines(y, list, color, last)
    for k, l in ipairs(list) do
      if y > last then break end
      if y == last and k < #list then say(5, y, ("… and %d more"):format(#list - k + 1), C.dim); return y + 1 end
      local cl = color or ((l:sub(1, 1) == "+" and C.good) or (l:sub(1, 1) == "-" and C.bad) or C.warn)
      say(5, y, l, cl)
      y = y + 1
    end
    return y
  end

  local function drawReview()
    local ok, why = ed.check()
    header(ok and ("Save " .. env.cfgPath .. "?  The current file is kept as lumen.cfg.bak.") or "Can't save yet", ok and C.accent or C.bad)
    local changes, warnings = ed.changes(), ed.warnings()
    if shrc() then changes[#changes + 1] = S.boot and "+ start lumen on boot (.shrc)" or "- don't start lumen on boot (.shrc)" end
    local y = 3
    if not ok then say(3, y, why, C.bad); y = y + 2 end
    say(3, y, #changes == 0 and "Nothing changed (saving rewrites the file with every setting)." or "Changes", C.text)
    local half = #warnings > 0 and math.floor((H - 6) * 0.6) or H - 3
    y = lines(y + 1, changes, nil, 3 + half)
    if #warnings > 0 then
      y = y + 1
      f:text(3, y, "Warnings", C.warn)
      lines(y + 1, warnings, C.warn, H - 2)
    end
    local x = 2
    if ok then
      x = button(x, FOOT, "SAVE", function()
        local done, err = pcall(function()
          local saved, e = files.commit(env.cfgPath, files.finish(ed.result()), env.shrcPath, shrc())
          if not saved then error(e, 0) end
        end)
        if not done then flash(tostring(err), false); S.view = "edit"; return end
        ed = Editor.new(files.loadOld(env.cfgPath), ed.snap)
        S.boot = files.bootPresent(env.shrcPath)
        S.view = "saved"
      end, true)
    end
    button(x, FOOT, "BACK", function() S.view = "edit" end)
  end

  local PAIR_TEXT = {
    "Which reactor does each switch run? LUMEN can find out by trying them, one at a time:",
    "",
    "  1. Every redstone switch's output goes off, so its reactor stops.",
    "  2. Each switch turns on alone, for up to 15 s, while LUMEN watches every reactor.",
    "  3. The reactor that starts making power is that switch's source; the switch goes off again.",
    "  4. At the end, every output goes back to how it was.",
    "",
    "Each reactor runs for a few seconds: have its coolant (and SFM) ready. A switch whose fault input",
    "says trouble is skipped. STOP puts every output back at once. APPLY sets the sources in this",
    "editor; nothing is written until SAVE.",
  }

  local function pairStatus(r, p)
    local sw = ed.c.control[r.i] or {}
    if r.status == "testing" then
      return ("▶ on now, watching every reactor… %ds"):format(math.floor(uptime() - (p.at or uptime()))), C.info
    end
    if r.status == "paired" then
      local name = ed.sourceName(r.reactor) or ("reactor " .. r.reactor:sub(1, 8))
      local t = ("✓ %s, after %ds"):format(name, math.floor(r.took or 0))
      if r.was and r.was ~= name then return t .. " (was " .. r.was .. ")", C.info end
      return t, C.good
    end
    if r.status == "none" then return "✗ nothing started in 15 s: check its wiring", C.bad end
    if r.status == "many" then return "✗ more than one started: " .. tostring(r.note), C.warn end
    if r.status == "skipped" then return "– skipped: " .. tostring(r.note), C.dim end
    if r.status == "stopped" then return "stopped", C.dim end
    return sw.redstone and "waiting" or "", C.dim
  end

  local function drawPair()
    local p = S.pair
    header("Pair switches with reactors")
    if not p then
      for k, l in ipairs(PAIR_TEXT) do say(3, 2 + k, l, k <= 2 and C.text or C.dim) end
      local n = 0
      for _, sw in ipairs(ed.c.control) do if sw.redstone then n = n + 1 end end
      say(3, 4 + #PAIR_TEXT, ("%d redstone switches, %d reactors found."):format(n, #(ed.snap.reactors or {})),
        (n > 0 and #(ed.snap.reactors or {}) > 0) and C.text or C.warn)
      local x = button(2, FOOT, "START", function()
        if n == 0 or #(ed.snap.reactors or {}) == 0 then
          flash("Nothing to pair: it needs redstone switches and reactors.", false)
          return
        end
        S.pair = Pair.new(component, ed)
        S.pair:step(uptime())
      end, true)
      button(x, FOOT, "BACK", function() S.view = "edit" end)
      if S.msg then say(3, MSG, S.msg, S.msgOk and C.good or C.bad) end
      return
    end
    f:text(4, 3, "SWITCH", C.dim); f:text(14, 3, "DRIVES", C.dim); f:text(31, 3, "FOUND", C.dim)
    local height = H - 5
    local at = 1
    for k, r in ipairs(p.rows) do if r == p.current then at = k end end
    local first = math.max(0, math.min(#p.rows - height, at - math.floor(height / 2)))
    local counts = { paired = 0, none = 0, many = 0, skipped = 0, waiting = 0, testing = 0, stopped = 0 }
    for _, r in ipairs(p.rows) do counts[r.status] = (counts[r.status] or 0) + 1 end
    for k = 1, height do
      local r, y = p.rows[first + k], 3 + k
      if r then
        local sw = ed.c.control[r.i] or {}
        local bg = r == p.current and C.sel or C.bg
        f:rowBg(y, bg)
        local text, colour = pairStatus(r, p)
        f:text(2, y, "●", colour, bg)
        f:text(4, y, fit(r.name, 9), C.text, bg)
        f:text(14, y, fit(sw.redstone and (sw.redstone .. " " .. Editor.sideName(sw.side)) or "GT machine", 16), C.dim, bg)
        f:text(31, y, fit(text, W - 31), colour, bg)
      end
    end
    local summary = ("%d paired · %d found nothing · %d skipped · %d to go"):format(counts.paired, counts.none + counts.many,
      counts.skipped, counts.waiting + counts.testing)
    say(3, MSG, p.err and ("Stopped: " .. p.err) or summary, p.err and C.bad or C.text)
    if not p.done then
      button(2, FOOT, "STOP", function() p:stop(); flash("Stopped: every output is back as it was.") end, false, C.bad)
    else
      local n = #p:found()
      local x = 2
      if n > 0 then
        x = button(x, FOOT, ("APPLY %d PAIRS"):format(n), function()
          for _, pr in ipairs(p:found()) do ed.pairSource(pr.i, pr.reactor) end
          S.pair, S.view, S.tab = nil, "edit", "switches"
          flash(("%d sources set: check them, then SAVE."):format(n))
        end, true)
      end
      button(x, FOOT, "BACK", function() S.pair, S.view = nil, "edit" end)
    end
  end

  local function drawSaved()
    header("Saved " .. env.cfgPath, C.good)
    say(3, 3, "The old file is " .. env.cfgPath .. ".bak.", C.text)
    say(3, 4, "Start lumen (or restart it) to use it.", C.text)
    local x = button(2, FOOT, "QUIT", function() S.running = false end)
    button(x, FOOT, "KEEP EDITING", function() S.view = "edit" end)
  end

  local function draw()
    f = frame.new(W, H)
    if S.view == "pick" then drawPick()
    elseif S.view == "pair" then drawPair()
    elseif S.view == "review" then drawReview()
    elseif S.view == "saved" then drawSaved()
    else drawEdit() end
    frame.paint(ui, painted, f)
    hits = f.hits
  end

  ---------------------------------------------------------------- events
  local function onKey(char, code)
    local fo = S.focus
    if fo then
      if code == KEY.enter then commitFocus(); return true end
      if code == KEY.esc then S.focus = nil; return true end
      if code == KEY.back then fo.text = unicode.sub(fo.text, 1, -2); return true end
      if char and char >= 32 and char < 127 and unicode.len(fo.text) < 40 then fo.text = fo.text .. string.char(char); return true end
      return false
    end
    if S.view ~= "edit" then return false end
    if code == KEY.up then moveSel(-1); return true end
    if code == KEY.down then moveSel(1); return true end
    if code == KEY.left or code == KEY.right then
      local at = 1
      for k, t in ipairs(TABS) do if t.id == S.tab then at = k end end
      S.tab = TABS[(at - 1 + (code == KEY.left and -1 or 1)) % #TABS + 1].id
      return true
    end
    return false
  end

  local function main()
    ui.fill(1, 1, W, H, C.bg)
    draw()
    while S.running do
      local pairing = S.view == "pair" and S.pair and not S.pair.done
      local ev = table.pack(event.pullMultiple(pairing and 0.5 or 60, "touch", "key_down", "scroll", "interrupted"))
      local name, redraw = ev[1], false
      if name == "touch" then
        -- touch: screenAddress, x, y, button, player
        local confirming = S.confirm
        S.msg = nil
        if not frame.tap(hits, math.floor(ev[3]), math.floor(ev[4])) then commitFocus() end
        if confirming and S.confirm == confirming then S.confirm = nil end
        redraw = true
      elseif name == "scroll" then
        -- scroll: screenAddress, x, y, direction (1 = up)
        if S.view == "edit" and S.tab ~= "general" then scrollBy(-(ev[5] or 0)); redraw = true end
      elseif name == "key_down" then
        -- key_down: keyboardAddress, char, code, player
        redraw = onKey(ev[3], ev[4])
      elseif name == "interrupted" then
        S.running = false
      end
      if pairing and S.running and not S.pair.done then S.pair:step(uptime()); redraw = true end
      if S.running and redraw then draw() end
    end
  end

  local ok, err = xpcall(main, debug.traceback)
  if S.pair and not S.pair.done then S.pair:stop() end   -- never leave a reactor switched by PAIR
  ui.restore()
  require("term").clear()
  if not ok then error(err, 0) end
  return S.result
end

return Screen
