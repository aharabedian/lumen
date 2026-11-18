--[[ lumen.setup.files: what both of lumen-setup's modes read and write. Shared by the text steps and the screen.

  loadOld(path) -> c          lumen.cfg as a plain table ({} when there's none); raises when it can't be read
  bootPresent(path) -> bool   whether .shrc starts lumen
  shrcText(path, want) -> text | nil   .shrc with the lumen line added (want) or removed; other lines are kept.
                              nil when nothing changes
  finish(c) -> text           c with every default filled in (nil-able ones left nil), rendered; raises when the
                              result wouldn't load (a bug in lumen-setup)
  commit(cfgPath, text, shrcPath, shrc?) -> true | nil, err   the old file kept as .bak, then the new one;
                              .shrc too when shrc isn't nil
]]

local config = require("lumen.config")
local render = require("lumen.setup.render")

local F = {}

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
F.read = read

local function write(path, text)
  local f, err = io.open(path .. ".new", "w")
  if not f then return false, err end
  f:write(text)
  f:close()
  os.remove(path)
  return os.rename(path .. ".new", path)
end

function F.loadOld(path)
  local text = read(path)
  if not text then return {} end
  local chunk, err = load(text, "=" .. path, "t", {})
  if not chunk then error(path .. " can't be read (" .. err .. "): fix or delete it first", 0) end
  local ok, c = pcall(chunk)
  if not ok or type(c) ~= "table" then error(path .. " can't be read: fix or delete it first", 0) end
  return c
end

local function lines(path)
  local text = read(path) or ""
  local out, present = {}, false
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local word = line:match("^%s*(%S+)")
    local prog = word and word:gsub("^.*/", ""):gsub("%.lua$", "")
    if prog == "lumen" then present = true else out[#out + 1] = line end
  end
  if out[#out] == "" then out[#out] = nil end
  return out, present
end

function F.bootPresent(path) return select(2, lines(path)) end

function F.shrcText(path, want)
  local out, present = lines(path)
  if want == present then return nil end
  if want then out[#out + 1] = "lumen" end
  return #out > 0 and (table.concat(out, "\n") .. "\n") or ""
end

-- Settings that mean "off" when nil stay nil; every other default is written out.
local NILABLE = { lensToken = true, lensPort = true, inputDrop = true, maxPassiveLoss = true, wakePlayers = true, operators = true }

function F.finish(c)
  for k, v in pairs(config.DEFAULTS) do
    if c[k] == nil and not NILABLE[k] then c[k] = type(v) == "table" and {} or v end
  end
  local text = render.cfg(c)
  -- What's saved must load: a mistake here is a bug in lumen-setup, not something to write.
  local chunk = load(text, "=lumen.cfg", "t", {})
  local ran, saved = pcall(chunk or error)
  local ok, why = config.check(ran and saved or nil)
  if not ok then error("lumen-setup made a config that doesn't load (" .. tostring(why) .. ") - please report it", 0) end
  return text
end

function F.commit(cfgPath, text, shrcPath, shrc)
  local old = read(cfgPath)
  if old then
    local ok, err = write(cfgPath .. ".bak", old)
    if not ok then return nil, "can't write " .. cfgPath .. ".bak: " .. tostring(err) end
  end
  local ok, err = write(cfgPath, text)
  if not ok then return nil, "can't write " .. cfgPath .. ": " .. tostring(err) end
  if shrc then
    ok, err = write(shrcPath, shrc)
    if not ok then return nil, "can't write " .. shrcPath .. ": " .. tostring(err) end
  end
  return true
end

return F
