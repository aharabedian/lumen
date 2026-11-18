--[[ lumen.supplies: counting what generators burn and make (fuel rods, coolant, benzene, spent rods...) in an AE2
  ME system, through an adapter on an ME interface or controller ("me_interface" | "me_controller"). Only reads:
  one lookup each, getItemInNetwork(name, damage) or getFluidInNetwork(name), a tick each.

  supplies.new(component, cfg) -> s       cfg.supplies: { { name, item, damage | fluid, below, above, hours, feeds }... }
  s:read() -> { { name, kind = "item" | "fluid", amount (items, or L of a fluid; 0 when there's none), label,
                  ok, err, cfg }... }       in cfg.supplies order
  supplies.find(component) -> address | nil   the ME component used (an interface first)
  supplies.search(component, text) -> s | nil, err   lumen-setup's search: every word of `text` in a name
    s:step(n) -> busy                   looks at up to n more items (the first step also asks for the exact name and
                                        lists the fluids); false once it's looked at them all, or after s:stop()
    s.results = { { kind, name, damage, label, amount, score }... }   best first, MAX_RESULTS at most
    s.looked (items looked at), s.done, s.err, s.began (computer.uptime() at the first step), s:stop()
    It walks the ME system with allItems(), an item at a time, so a big one never has to fit in this computer.
  supplies.score(text, label, name) -> number | nil   how well a name matches: every word of text in label or
                                       name (any case, any order), or nil; whole names, words starting words, and
                                       shorter labels rank higher
  supplies.MAX_RESULTS
  supplies.unit(kind) -> "" | " L"
  supplies.status(r) -> level ("bad" | "warn" | nil), text   a reading with rate (per hour) and lasts (seconds):
                                       "none left", "low", "piling up", "lasts 8h57m", "can't be counted"; when fine,
                                       "lasts 3d 6h", "+4.00/h" or "steady"
]]

local power = require("lumen.power")

local supplies = {}

function supplies.status(r)
  local c = r.cfg or {}
  if not r.ok then return "warn", "can't be counted" end
  if c.below and r.amount <= 0 then return "bad", "none left" end
  if c.below and r.amount < c.below then return "warn", "low" end
  if c.above and r.amount > c.above then return "warn", "piling up" end
  local lasts = r.lasts and ("lasts " .. power.duration(r.lasts)) or nil
  if c.hours and r.lasts and r.lasts < c.hours * 3600 then return "warn", lasts end
  if lasts then return nil, lasts end
  if r.rate and r.rate > 0.5 then return nil, "+" .. power.si(r.rate) .. "/h" end
  return nil, "steady"
end

local TYPES = { "me_interface", "me_controller" }

function supplies.find(component)
  for _, t in ipairs(TYPES) do
    local address = component.list(t, true)()
    if address then return address end
  end
end

function supplies.unit(kind) return kind == "fluid" and " L" or "" end

local S = {}
S.__index = S

function supplies.new(component, cfg) return setmetatable({ component = component, cfg = cfg }, S) end

local function reason(err) return (tostring(err):gsub("^[^:]*:%d+: ", "")) end

function S:read()
  local out = {}
  local list = self.cfg.supplies or {}
  if #list == 0 then return out end
  local address = supplies.find(self.component)
  local proxy = address and self.component.proxy(address)
  for _, c in ipairs(list) do
    local r = { name = c.name, kind = c.fluid and "fluid" or "item", cfg = c, ok = false }
    if not proxy then
      r.err = "no ME interface or controller (an adapter on one)"
    else
      local ok, v = pcall(function()
        if c.fluid then return proxy.getFluidInNetwork(c.fluid) end
        return proxy.getItemInNetwork(c.item, c.damage or 0)
      end)
      if not ok then r.err = reason(v)
      else
        r.ok = true
        r.amount = type(v) == "table" and (tonumber(c.fluid and v.amount or v.size) or 0) or 0
        r.label = type(v) == "table" and v.label or nil
      end
    end
    out[#out + 1] = r
  end
  return out
end

supplies.MAX_RESULTS = 30

local function words(text)
  local out = {}
  for w in tostring(text):lower():gmatch("[%w]+") do out[#out + 1] = w end
  return out
end

function supplies.score(text, label, name)
  local ws = words(text)
  if #ws == 0 then return nil end
  label, name = tostring(label or ""):lower(), tostring(name or ""):lower()
  local score = 0
  for _, w in ipairs(ws) do
    local at = label:find(w, 1, true)
    if at then
      score = score + ((at == 1 or not label:sub(at - 1, at - 1):match("%w")) and 3 or 2)
    elseif name:find(w, 1, true) then
      score = score + 1
    else
      return nil
    end
  end
  local whole = table.concat(ws, " ")
  local plain = table.concat(words(label), " ")
  if plain == whole then score = score + 10 elseif plain:sub(1, #whole) == whole then score = score + 2 end
  return score - #label / 100
end

local Search = {}
Search.__index = Search

function supplies.search(component, text)
  local address = supplies.find(component)
  local proxy = address and component.proxy(address)
  if not proxy then return nil, "no ME interface or controller found (put an adapter on one)" end
  if #words(text) == 0 then return nil, "type part of its name" end
  return setmetatable({ proxy = proxy, text = text, results = {}, looked = 0, seen = {} }, Search)
end

function Search:add(kind, it, label)
  local key = kind .. ":" .. tostring(it.name) .. ":" .. tostring(it.damage or 0)
  if self.seen[key] then return end
  local score = supplies.score(self.text, label, it.name)
  if not score then return end
  self.seen[key] = true
  local r = { kind = kind, name = it.name, damage = kind == "item" and (it.damage or 0) or nil, label = label,
    amount = (kind == "fluid" and it.amount or it.size) or 0, score = score }
  local list = self.results
  list[#list + 1] = r
  table.sort(list, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.label < b.label end)
  if #list > supplies.MAX_RESULTS then list[#list] = nil end
end

function Search:stop() self.done = true end

function Search:step(n)
  if self.done then return false end
  local proxy = self.proxy
  if not self.walk then
    -- The exact name first (AE2 matches it on the server, at once), and the fluids (there are few).
    local ok, items = pcall(function() return proxy.getItemsInNetwork({ label = self.text }) end)
    if ok then for _, it in ipairs(items or {}) do self:add("item", it, it.label or it.name) end end
    local okF, fluids = pcall(function() return proxy.getFluidsInNetwork() end)
    if okF then for _, fl in ipairs(fluids or {}) do self:add("fluid", fl, tostring(fl.label or fl.name)) end end
    local okW, walk = pcall(function() return proxy.allItems() end)
    if not okW or not walk then self.err, self.done = okW and "the ME system has no item list" or reason(walk), true; return false end
    self.walk = walk
  end
  for _ = 1, n do
    local ok, it = pcall(self.walk)
    if not ok then self.err, self.done = reason(it), true; return false end
    if it == nil then self.done = true; return false end
    self.looked = self.looked + 1
    if type(it) == "table" then self:add("item", it, it.label or it.name) end
  end
  return true
end

return supplies
