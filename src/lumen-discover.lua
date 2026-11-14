--[[ lumen-discover.lua - what this computer's components offer, and what they read, to build LUMEN
  against the game's real API (LSCs, generators, other GT power blocks).

  Usage:
    lumen-discover [text] [--all]   components; methods (with docs) of those whose type contains `text`
                                    (--all: also the basics every computer has: gpu, screen, filesystem...)
    lumen-discover --read [type]    what every read-only method (get..., is..., has..., no arguments) of each
                                    `type` component returns (default gt_machine). Never calls anything else.
    lumen-discover --probe          IC2 reactors and transposers, for reactor control: the reactor's methods,
                                    getSlotInfo, each transposer side's inventory and stacks, timed. Read only.
    lumen-discover --probe --pause  also pauses each producing reactor with setActive(false) for 5 s, reading
                                    heat and its parts' damage every second, then puts it back as it was.
  Everything is also written to /home/lumen-discover.txt (on your own machine:
  saves/<world>/opencomputers/<disk address>/home/lumen-discover.txt).
]]

if not package.path:find("/home/lib/?.lua", 1, true) then package.path = package.path .. ";/home/lib/?.lua" end
for name in pairs(package.loaded) do if name:find("^lumen%.") then package.loaded[name] = nil end end
if not pcall(require, "lumen.version") then error("LUMEN's modules are missing from /home/lib/lumen - run lumen-update", 0) end

local component = require("component")
local discover  = require("lumen.discover")
local VERSION   = require("lumen.version")

local args = { ... }
local opts, readType, probe = {}, nil, nil
for i, a in ipairs(args) do
  if a == "--all" then opts.all = true
  elseif a == "--probe" then probe = probe or {}
  elseif a == "--pause" then probe = probe or {}; probe.pause = true
  elseif a == "--read" then readType = args[i + 1] or "gt_machine"
  elseif args[i - 1] ~= "--read" then opts.filter = a end
end

local lines = { "lumen-discover " .. VERSION, "" }
print("lumen-discover " .. VERSION)
if probe then
  probe.sleep = os.sleep
  for _, l in ipairs(discover.probe(component, require("computer"), probe)) do print(l); lines[#lines + 1] = l end
elseif readType then
  for _, l in ipairs(discover.read(component, readType)) do print(l); lines[#lines + 1] = l end
else
  local report, summary = discover.report(component, opts)
  for _, l in ipairs(summary) do print("  " .. l); lines[#lines + 1] = l end
  lines[#lines + 1] = ""
  for _, l in ipairs(report) do lines[#lines + 1] = l end
end

local out = (os.getenv("LUMEN_PREFIX") or "") .. "/home/lumen-discover.txt"
local f, err = io.open(out, "w")
if not f then error("can't write " .. out .. ": " .. tostring(err), 0) end
f:write(table.concat(lines, "\n"), "\n")
f:close()
print("written to " .. out)
