-- test_setup.lua: lumen-setup with scripted answers. A first run in a power room (two LSCs, a vacuum reactor,
-- an LFTR, a blast furnace, a Redstone I/O block): names, sources, a redstone switch, alerts, LENS, .shrc; the
-- file it writes loads and lumen runs it. A re-run keeps everything. Also: a GT machine switch, cancelling,
-- declining, and a broken existing config.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local LSC = require("lsc")
local Gen = require("gen")
local Net = require("net")
local check = H.check
local config = require("lumen.config")

local prefix = H.TMP .. "/root"
local home = prefix .. "/home"
os.execute('mkdir -p "' .. home .. '"')
local realGetenv = os.getenv
os.getenv = function(k) if k == "LUMEN_PREFIX" then return prefix end return realGetenv(k) end -- luacheck: ignore 122
local CFG, SHRC = home .. "/lumen.cfg", home .. "/.shrc"

local function read(p) local f = io.open(p); if not f then return nil end; local t = f:read("*a"); f:close(); return t end

local main = LSC.new{ stored = 9e9, capacity = 1e10 }
local spare = LSC.new{ stored = 1e9, capacity = 4e9 }
local reactor = Gen.reactor{ heat = 0, maxHeat = 10000, output = 0, produces = false }
local lftr = Gen.gt("gtpp.multimachine.lftr", { active = true })
local ebf = Gen.gt("multimachine.blastfurnace", { active = true })
local rs = Gen.redstone()
M.components = {
  ["d2440f27-52c9"] = main.entry, ["0aaa1111-0000"] = spare.entry, ["eeee0000-0000"] = reactor.entry,
  ["a1b20000-0000"] = lftr.entry, ["ebf00000-0000"] = ebf.entry, ["5e1f0000-0000"] = rs.entry,
}
M.modem = Net.new():endpoint("lumen")

local function setup(answers)
  local out = {}
  local realPrint, realWrite, realRead = print, io.write, io.read
  print = function(...) -- luacheck: ignore 121
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    out[#out + 1] = table.concat(parts, "\t") .. "\n"
  end
  io.write = function(...) for _, s in ipairs({ ... }) do out[#out + 1] = tostring(s) end end -- luacheck: ignore 122
  local i = 0
  io.read = function() i = i + 1; return answers[i] end   -- luacheck: ignore 122 (nil after the last = Ctrl+D)
  local ok, err = pcall(H.run, "lumen-setup.lua")
  print, io.write, io.read = realPrint, realWrite, realRead -- luacheck: ignore 121 122
  return table.concat(out), ok, err
end
local out
local function has(s) return out:find(s, 1, true) ~= nil end

---------------------------------------------------------------- first run
local f = assert(io.open(SHRC, "w")); f:write("echo hello\n"); f:close()
local ok
out, ok = setup({
  "Spare", "Main",                  -- LSC names, by address: 0aaa1111, d2440f27
  "", "LFTR", "y",                  -- the LFTR: show it (a generator by its name), its name, always on
  "",                               -- the blast furnace: no (the default for a machine that isn't a generator)
  "Vac nuke",                       -- the reactor's name
  "y",                              -- add a switch
  "Vac nuke",                       -- its name
  "1",                              -- a redstone signal (the only redstone component is picked by itself)
  "3",                              -- north
  "",                               -- a signal means stop: no
  "", "",                           -- on below 30, off above 90
  "1",                              -- all LSCs together
  "3",                              -- its source: Vac nuke
  "n",                              -- add another: no
  "", "", "", "",                   -- alerts: fill 25 / 10, drain 4 / 1
  "",                               -- input alert: no
  "y", "", "power-room", "-",       -- LENS: yes, 4243, power-room, no token
  "",                               -- start on boot: yes
  "",                               -- save
})
check(ok, "lumen-setup runs" .. (ok and "" or (": " .. out:sub(-300))))
check(has("LSC 0aaa1111 (25.0% full)") and has("LSC d2440f27 (90.0% full)"), "lists the LSCs with their fill")
check(has("an IC2 reactor (eeee0000)"), "finds the reactor")
check(has("show gtpp.multimachine.lftr (a1b20000) as a power source? (y/n) [y]")
  and has("show multimachine.blastfurnace (ebf00000) as a power source? (y/n) [n]"),
  "offers GT machines: generators by default, others not")
check(has("which side does the signal go out of?"), "asks the redstone side")
check(has("This will be saved to " .. CFG) and has("saved: 2 LSC name(s), 2 source(s), 1 switch(es)"), "shows the file and saves it")
local text = read(CFG)
check(text:find("-- lumen.cfg - written by lumen-setup", 1, true) and text:find("lowFill = 25,%s+%-%- warn below") ~= nil,
  "the file is commented")
local c, err = config.load(CFG)
check(c ~= nil, "the file loads" .. (c and "" or (": " .. tostring(err))))
check(c.names["0aaa1111"] == "Spare" and c.names["d2440f27"] == "Main", "names")
check(#c.sources == 2 and c.sources[1].name == "LFTR" and c.sources[1].alwaysOn and c.sources[2].name == "Vac nuke",
  "sources: the LFTR (always on) and the reactor, named")
local sw = c.control[1]
check(sw and sw.name == "Vac nuke" and sw.redstone == "5e1f0000" and sw.side == "north" and sw.onBelow == 30
  and sw.offAbove == 90 and sw.lsc == nil and sw.source == "Vac nuke" and not sw.invert, "the switch")
check(c.lensPort == 4243 and c.lensNode == "power-room" and c.lensToken == nil and c.inputDrop == nil, "LENS, no input alert")
check(read(SHRC) == "echo hello\nlumen\n", ".shrc starts lumen, other lines kept")

---------------------------------------------------------------- lumen runs what it wrote
M.setTime(0)
M.onPull = function(n) if n > 3 then return { "interrupted" } end end
local runOk, runErr = pcall(H.run, "lumen.lua", CFG)
M.onPull = nil
check(runOk and M.find("POWER", 3) and M.find("Vac nuke", 3) and M.find("LFTR", 3), "lumen runs it: POWER shows the switch and sources"
  .. (runOk and "" or (": " .. tostring(runErr))))

---------------------------------------------------------------- a re-run keeps everything
local before = read(CFG)
out, ok = setup({
  "", "",              -- names kept
  "",                  -- reactor name kept
  "", "", "",          -- LFTR: yes, name, always on: kept
  "",                  -- blast furnace: no
  "",                  -- keep the switch
  "",                  -- add a switch: no
  "", "", "", "", "",  -- alerts kept
  "", "", "", "",      -- LENS kept (token: Enter = none)
  "",                  -- start on boot (already there)
  "",                  -- save
})
check(ok and has("Vac nuke: redstone 5e1f0000 north, on below 30%, off above 90%"), "a re-run lists the switches")
check(read(CFG) == before, "Enter all the way: the same file")
check(read(CFG .. ".bak") == before, "the old file is kept as .bak")
check(read(SHRC) == "echo hello\nlumen\n", ".shrc unchanged")

---------------------------------------------------------------- a GT machine switch; cancel; decline; broken
out, ok = setup({ "", "", "", "", "", "", "",
  "n",                 -- don't keep the switch
  "y", "LFTR", "2", "1", "50", "95", "1", "1", "n",
  "", "", "", "", "y", "", "", "", "", "", "", "" })
c = config.load(CFG)
check(ok and #c.control == 1 and c.control[1].machine == "a1b20000" and c.control[1].onBelow == 50 and c.inputDrop == 50,
  "a switch on a GT machine's work switch (the LFTR); the input alert")

local saved = read(CFG)
out, ok = setup({ "", "" })
check(ok and has("cancelled - nothing saved") and read(CFG) == saved, "Ctrl+D cancels, nothing saved")
out, ok = setup({ "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "n" })
check(ok and has("nothing saved") and read(CFG) == saved, "no to Save: nothing saved")
f = assert(io.open(CFG, "w")); f:write("return {"); f:close()
out, ok = setup({})
check(not ok and tostring(select(3, setup({}))):find("fix or delete it first", 1, true), "a broken config is left alone, and says so")
M.modem = nil

H.done()
