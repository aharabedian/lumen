-- test_setup_screen.lua: lumen-setup's touchscreen editor. First the editor alone (pure): COPY's next name and
-- next redstone block, checks on marks and names, renames that switches follow, changes and warnings. Then the
-- screen, by taps and typing, in a power room with 12 vacuum reactors, each with its own Redstone I/O block: one
-- switch set up by hand and copied 11 times, a source picked, READ finding a block by its signal, LENS and start
-- on boot, SAVE; the file loads and lumen runs it. Also: tier 2 fits, unsaved changes need a second QUIT, TEXT
-- SETUP, and a screen too small falls back to the text setup.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local Gen = require("gen")
local Net = require("net")
local check = H.check
local config = require("lumen.config")
local Editor = require("lumen.setup.editor")

---------------------------------------------------------------- the editor alone
local function addr(c, k) return ("%s%03d0000-0000"):format(c, k) end
local snap = { lscs = { { address = "d2440f27-52c9", ok = true, fill = 0.5 } }, reactors = {}, gts = {}, redstone = {}, modem = true }
for k = 1, 3 do
  snap.reactors[k] = addr("e", k)
  snap.redstone[k] = addr("c", k)
end
local ed = Editor.new({}, snap)
check(#ed.c.sources == 3 and ed.c.sources[1].name == "Reactor e001" and ed.c.sources[1].address == "e0010000",
  "reactors found are sources, named by address")
local i = ed.addSwitch()
local sw = ed.c.control[i]
check(sw.name == "Switch 1" and sw.redstone == "c0010000" and sw.side == "north" and sw.onBelow == 30 and sw.offAbove == 90,
  "+ NEW: the first redstone block no switch uses, north, 30-90%")
check(ed.setSwitch(i, "name", "MOX 1") and ed.setSwitch(i, "side", "top"), "name and side")
check(not ed.setSwitch(i, "onBelow", 95) and select(2, ed.setSwitch(i, "onBelow", 95)):find("under off above", 1, true),
  "on below must be under off above")
check(not ed.setSwitch(i, "offAbove", 101) and not ed.setSwitch(i, "name", ""), "and off above a percent, a name not blank")
check(ed.setFault(i, "on", true) and sw.fault.redstone == "c0010000" and sw.fault.side == "south" and sw.fault.stop == true,
  "a fault input: the same block, south, stops")
ed.setFault(i, "latch", true)
ed.setSource("e0010000", "name", "MOX 1")
ed.setSwitch(i, "source", "MOX 1")
local j = ed.copySwitch(i)
local cp = ed.c.control[j]
check(j == 2 and cp.name == "MOX 2" and cp.redstone == "c0020000" and cp.side == "top" and cp.fault.redstone == "c0020000"
  and cp.fault.latch and cp.source == nil, "COPY: MOX 2 on the next block, its fault line with it, no source")
check(ed.copySwitch(j) == 3 and ed.c.control[3].redstone == "c0030000", "and MOX 3 on the third")
check(ed.copySwitch(3) == 4 and ed.c.control[4].name == "MOX 4" and ed.c.control[4].redstone == "c0010000",
  "a fourth with no free block left: the first found (a warning says so)")
local w = table.concat(ed.warnings(), "\n")
check(w:find("switches MOX 1 and MOX 4 both drive redstone c0010000 top", 1, true), "warning: two switches on one output")
check(w:find("MOX 1 reads its fault on redstone c0010000 south", 1, true) == nil, "a fault on another side of its block is fine")
ed.deleteSwitch(4)
ed.setSource("e0010000", "name", "MOX one")
check(ed.c.control[1].source == "MOX one", "renaming a source: switches follow it")
check(not ed.setSource("e0020000", "name", "MOX one"), "two sources can't share a name")
ed.setFault(2, "side", "top")
check(table.concat(ed.warnings(), "\n"):find("MOX 2 reads its fault on redstone c0020000 top, which MOX 2 drives", 1, true),
  "warning: a fault read on the side the switch drives")
ed.setFault(2, "side", "south")
ed.nameLsc("d2440f27", "Main")
ed.setSwitch(1, "lsc", "Main")
ed.nameLsc("d2440f27", "Big")
check(ed.c.control[1].lsc == "Big", "renaming an LSC: switches follow it")
local ch = ed.choices("redstone", 1)
check(#ch == 3 and ch[1].note == "used by MOX 1 (signal top), MOX 1 (fault south)" and ch[3].note:find("MOX 3", 1, true),
  "choices say who uses each block")
check(ed.check(), "the result passes lumen.config's checks")
local changes = table.concat(ed.changes(), "\n")
check(changes:find("+ switch MOX 2: redstone c0020000 top, on below 30%, off above 90%, fault from c0020000 south (latch)", 1, true)
  and changes:find("+ LSC d2440f27: Big", 1, true) and changes:find("+ source e0010000: MOX one", 1, true),
  "changes: switches, LSC names, sources")
local ed2 = Editor.new(ed.result(), snap)
check(#ed2.changes() == 0, "the result opened again: no changes")
ed2.setSwitch(1, "kind", "machine")
check(not ed2.setSwitch(1, "kind", "machine") or ed2.c.control[1].redstone == nil, "a switch can't be a GT machine with none found")

---------------------------------------------------------------- the screen
local prefix = H.TMP .. "/root"
local home = prefix .. "/home"
os.execute('mkdir -p "' .. home .. '"')
local realGetenv = os.getenv
os.getenv = function(k) if k == "LUMEN_PREFIX" then return prefix end return realGetenv(k) end -- luacheck: ignore 122
local CFG, SHRC = home .. "/lumen.cfg", home .. "/.shrc"
local function read(p) local f = io.open(p); if not f then return nil end; local t = f:read("*a"); f:close(); return t end

local main = LSC.new{ stored = 5e9, capacity = 1e10 }
local lftr = Gen.gt("gtpp.multimachine.lftr", { active = true })
M.components = { ["d2440f27-52c9"] = main.entry, ["a1b20000-0000"] = lftr.entry }
local rs = {}
for k = 1, 12 do
  M.components[addr("e", k)] = Gen.reactor{ heat = 0, maxHeat = 10000, output = 0, produces = false }.entry
  rs[k] = Gen.redstone()
  M.components[addr("c", k)] = rs[k].entry
end
M.modem = Net.new():endpoint("lumen")

-- Each step runs when lumen-setup waits for an event, so it sees the screen as drawn. A step returns an event
-- to deliver, or nil (time passes, nothing happens).
local steps
local function at(x, y) return { "touch", "scr", x, y, 0, "p" } end
local function tap(text, minY, minX)
  return function()
    local x, y = M.find(text, minY, minX)
    if not x then
      local rows = {}
      for r = 1, M.H do rows[#rows + 1] = M.row(r) end
      error("nothing to tap: " .. text .. "\n" .. table.concat(rows, "\n"))
    end
    return at(x + 1, y)
  end
end
-- The field right of a label: `gap` columns after the label's start.
local function tapField(label, gap, minY)
  return function()
    local x, y = M.find(label, minY or 1)
    assert(x, "no field after " .. label)
    return at(x + gap, y)
  end
end
local function key(char, code) return function() return { "key_down", "kb", char, code, "p" } end end
local function typed(text)
  local out = {}
  for c in text:gmatch(".") do out[#out + 1] = key(c:byte(), 0) end
  out[#out + 1] = key(13, 28)
  return out
end
local function add(list) for _, s in ipairs(list) do steps[#steps + 1] = s end end
local function seen(fn) steps[#steps + 1] = function() fn(); return nil end end

local function setup(args)
  M.pulls = 0
  M.onPull = function()
    local s = table.remove(steps, 1)
    if s then return s() end
    return { "interrupted" }
  end
  local out = {}
  local realPrint, realWrite, realRead = print, io.write, io.read
  print = function(...) out[#out + 1] = table.concat({ ... }, "\t") end -- luacheck: ignore 121
  io.write = function(...) out[#out + 1] = table.concat({ ... }) end -- luacheck: ignore 122
  io.read = function() return nil end -- luacheck: ignore 122
  local ok, err = pcall(H.run, "lumen-setup.lua", args)
  print, io.write, io.read = realPrint, realWrite, realRead -- luacheck: ignore 121 122
  M.onPull = nil
  return ok, err, table.concat(out, "\n")
end

M.resize(160, 50)
local DET = 40      -- the detail panel starts at H - 10
local found = {}
steps = {}
seen(function()
  found.tabs = M.find(" LSCS 1 ", 2) and M.find(" SOURCES 12 ", 2) and M.find(" SWITCHES 0 ", 2) and M.find(" GENERAL ", 2)
  found.unsaved = M.find("unsaved changes", 1)    -- the 12 reactors are new sources
end)
add({ tap("d2440f27", 4), tapField("Name", 9, DET) })
add(typed("Main"))
seen(function() found.lsc = M.find("Main", 4) and M.find("50.0% full", 4) end)
add({ tap(" SOURCES 12 ", 2), tap("e0010000", 4), tapField("Name", 9, DET) })
-- Backspace the default name away, then type the new one.
for _ = 1, #"Reactor e001" do add({ key(0, 14) }) end
add(typed("MOX 1"))
seen(function() found.source = M.find("MOX 1", 4) and M.find("IC2 reactor", 4) end)
add({ tap(" SWITCHES 0 ", 2), tap(" + NEW ", 50) })
seen(function() found.new = M.find("Switch 1", 4) and M.find("redstone c0010000 north", 4) end)
add({ tapField("Name", 9, DET) })
for _ = 1, #"Switch 1" do add({ key(0, 14) }) end
add(typed("MOX 1"))
add({ tapField("on below", 10, DET) })
add({ key(0, 14), key(0, 14), key(0, 14) })
add(typed("95"))
seen(function() found.bad = M.find("on below must be a whole percent under off above (90%)", 49) end)
add({ tap(" top ", DET) })                         -- the switch's side (the first "top" in the panel)
add({ tap(" ON ", DET + 5), tap(" LATCH ", DET) })  -- a fault input, latched
add({ tap("none ▸", DET) })                        -- its source: the pick view
seen(function() found.pick = M.find("The source MOX 1 switches", 1) and M.find("Reactor e002", 3) end)
add({ tap("MOX 1", 3) })
seen(function()
  found.sw = M.find("MOX 1", 4) and M.find("redstone c0010000 top", 4) and M.find("30-90%", 4) and M.find("south, latch", 4)
end)
for _ = 1, 11 do add({ tap(" COPY ", DET) }) end
seen(function()
  found.copies = M.find(" SWITCHES 12 ", 2) and M.find("MOX 12", 4) and M.find("redstone c0120000 top", 4)
  found.copyMsg = M.find("Copied: pick its redstone block and source", 49)
end)
-- MOX 3: its source, and READ: a lever on its block's west side.
add({ tap("MOX 3 ", 4), tap("none ▸", DET), tap("Reactor e003", 3) })
seen(function() rs[3].inp[4] = 15 end)
add({ tap(" READ ", DET) })
seen(function() found.read = M.find("c0030000: signal in west 15", DET) end)
-- GENERAL: LENS on, start on boot.
add({ tap(" GENERAL ", 2) })
seen(function() found.general = M.find("Reactor heat", 4) and M.find("warn below", 4) end)
-- The ON button on a setting's own row.
local function onFor(label)
  return function()
    local _, y = M.find(label, 4)
    return at(M.find(" ON ", y) + 1, y)
  end
end
add({ onFor("LENS"), onFor("Start on boot") })
add({ tap(" SAVE ", M.H) })
seen(function()
  found.review = M.find("Save " .. CFG, 1) and M.find("+ switch MOX 12: redstone c0120000 top", 3)
    and M.find("+ start lumen on boot (.shrc)", 3) and M.find("+ LSC d2440f27: Main", 3)
end)
seen(function() H.screen("lumen-setup-review") end)
add({ tap(" SAVE ", M.H) })
seen(function() found.saved = M.find("Saved " .. CFG, 1) end)
add({ tap(" QUIT ", M.H) })
local ok, err = setup()
check(ok, "lumen-setup's screen runs" .. (ok and "" or (": " .. tostring(err))))
check(found.tabs and found.unsaved, "tabs with counts: 1 LSC, 12 sources (the reactors), no switches; unsaved changes")
check(found.lsc, "LSCS: tap one, type its name")
check(found.source, "SOURCES: a reactor renamed")
check(found.new, "+ NEW: Switch 1 on the first redstone block")
check(found.bad, "a bad mark says why")
check(found.pick and found.sw, "side, fault (latched) and a source picked from a list")
check(found.copies and found.copyMsg, "COPY x11: MOX 2 to MOX 12, each on its own block")
check(found.read, "READ: the block with a lever on, and on which side")
check(found.general, "GENERAL")
check(found.review, "SAVE: the changes first")
check(found.saved, "saved")

local c, cerr = config.load(CFG)
check(c ~= nil, "the file loads" .. (c and "" or (": " .. tostring(cerr))))
check(#c.control == 12 and c.names["d2440f27"] == "Main" and c.lensPort == 4243, "12 switches, the LSC's name, LENS")
local blocks, all = {}, true
for k, s in ipairs(c.control) do
  blocks[s.redstone] = true
  all = all and s.name == "MOX " .. k and s.side == "top" and s.redstone == ("c%03d0000"):format(k) and s.fault
    and s.fault.redstone == s.redstone and s.fault.side == "south" and s.fault.latch and s.onBelow == 30 and s.offAbove == 90
end
local nBlocks = 0
for _ in pairs(blocks) do nBlocks = nBlocks + 1 end
check(all and nBlocks == 12, "each MOX on its own block, top; its fault from the same block, south, latched")
check(c.control[1].source == "MOX 1" and c.control[3].source == "Reactor e003" and c.control[2].source == nil, "sources")
check(read(SHRC) == "lumen\n", ".shrc starts lumen")
check(read(CFG):find("-- lumen.cfg - written by lumen-setup", 1, true), "the same commented file the text setup writes")

M.setTime(0)
M.onPull = function(n) if n > 3 then return { "interrupted" } end end
local runOk, runErr = pcall(H.run, "lumen.lua", CFG)
M.onPull = nil
check(runOk and M.find("MOX 1 ", 3) and M.find("auto: on below 30%, off above 90%", 3),
  "lumen runs it" .. (runOk and "" or (": " .. tostring(runErr))))

-- Finished: every switch with its reactor. All twelve fit on the screen, one row each.
local whole = config.load(CFG)
for k, s in ipairs(whole.control) do
  if not s.source then
    s.source = "Reactor " .. ("e%03d"):format(k)
    for _, src in ipairs(whole.sources) do if src.address:sub(1, 4) == ("e%03d"):format(k) then src.name = s.source end end
  end
end
local CFG2 = home .. "/lumen-all.cfg"
local fh = assert(io.open(CFG2, "w"))
fh:write(require("lumen.setup.files").finish(whole))
fh:close()
M.onPull = function(n) if n > 3 then return { "interrupted" } end end
runOk, runErr = pcall(H.run, "lumen.lua", CFG2)
M.onPull = nil
check(runOk and M.find("MOX 12 ", 3) and not M.find(" more", 3) and not M.find("Reactor e0", 3),
  "12 reactors on switches: all twelve on screen, each reactor on its switch's row" .. (runOk and "" or (": " .. tostring(runErr))))

---------------------------------------------------------------- opened again; tier 2; quitting
M.resize(80, 25)
M.oob = 0
found = {}
steps = {}
seen(function() found.clean = not M.find("unsaved changes", 1) and M.find(" SWITCHES 12 ", 2) end)
add({ tap(" SWITCHES 12 ", 2), tap("MOX 1 ", 4) })
seen(function()
  found.fits = M.oob == 0 and M.find(" COPY ", 15) and M.find(" DELETE ", 15) and M.find(" OK SIGNAL ", 15)
    and M.find(" READ ", 15) and M.find("1-10 of 12", 3)
end)
seen(function() H.screen("lumen-setup") end)
add({ tap(" DELETE ", 15), tap(" DELETE ", 15) })
seen(function() found.deleted = M.find(" SWITCHES 11 ", 2) and M.find("unsaved changes", 1) end)
add({ tap(" QUIT ", 25) })
seen(function() found.confirm = M.find("Unsaved changes: tap QUIT again", 24) end)
add({ tap(" QUIT ", 25) })
local before = read(CFG)
ok, err = setup()
check(ok and found.clean, "opened again: nothing unsaved" .. (ok and "" or (": " .. tostring(err))))
check(found.fits, "tier 2: a switch's whole panel fits, the list scrolls")
check(found.deleted, "DELETE asks twice")
check(found.confirm and read(CFG) == before, "QUIT with unsaved changes asks again; nothing saved")

steps = { tap(" TEXT SETUP ", 25) }
local _, _, out = setup()
check(out:find("lumen-setup " .. require("lumen.version") .. " - Enter keeps", 1, true) and out:find("cancelled", 1, true),
  "TEXT SETUP: the text setup instead")
M.resize(50, 16)
steps = {}
_, _, out = setup()
check(out:find("the editor needs 80x25, so the text setup", 1, true), "a screen too small: the text setup")
M.resize(160, 50)
M.modem = nil

H.done()
