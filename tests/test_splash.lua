-- test_splash.lua: the SPECTRA logo lumen shows while it starts: the pixel art, its cells at both sizes,
-- and drawn on a tier 3 and a tier 2 screen.
local H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "helper.lua")
local M = require("oc")
local check = H.check
local splash = require("lumen.splash")
local Gui = require("lumen.gui")

local artOk = #splash.ART == 23
for _, row in ipairs(splash.ART) do artOk = artOk and #row == 25 and not row:find("[^.WOBG]") end
check(artOk, "the logo is 25 x 23 pixels of known colors")
local function width(runs) local n = 0; for _, r in ipairs(runs) do n = n + utf8.len(r[2]) end; return n end
local small, big = splash.rows(1), splash.rows(2)
check(#small == 12 and width(small[1]) == 25 and #big == 23 and width(big[1]) == 50, "25 x 12 cells, or 50 x 23 doubled")

local gpu = require("component").gpu
for _, size in ipairs({ { 160, 50, "splash" }, { 80, 25, "splash-tier2" } }) do
  M.resize(size[1], size[2])
  splash.show(gpu, size[1], size[2], "LUMEN", "9.9.9", Gui.C.accent)
  H.screen(size[3])
  local nx, ny = M.find("LUMEN  v9.9.9")
  check(M.find("S P E C T R A") and nx and M.fgAt(nx, ny) == Gui.C.accent,
    size[1] .. "x" .. size[2] .. ": the logo, SPECTRA and the name in LUMEN's color")
end

H.done()
