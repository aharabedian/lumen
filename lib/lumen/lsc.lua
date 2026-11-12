--[[ lumen.lsc: what an LSC (Lapotronic Supercapacitor, `gt_machine`) says about itself, from its own
  getSensorInformation lines, the figures its screen shows.

  lsc.parse(lines) -> info
    lines: the table getSensorInformation returns. Each line is a translation key, then values, split by
    backslashes; §-formatting codes are dropped. Numbers keep their exact value (commas removed; a value too
    big for an integer becomes a float). Fields are nil when the line is missing:
      stored, capacity       EU (the exact lines, not the 1.08x10^10 ones)
      used                   percent full (95.0)
      passiveLoss            EU/t
      inNow, outNow          EU/t, the "eu_in"/"eu_out" lines
      avgIn, avgOut          EU/t averages: { sec = , min5 = , hour1 = }, and window = seconds the "sec" one covers
      timeTo                 { to = "full" | "empty" | ..., text = "10.42 hours", seconds = 37512 } (seconds nil
                             for a unit we don't know)
      maintenance, wireless  the key's last word: "ok", "disabled"...
      capacitors             { UHV = 0, UEV = 0, ... } counts of each tier's capacitors
      wirelessEu             EU in the wireless network
      unknown                lines not understood, as they came
]]

local lsc = {}

local UNITS = {
  second = 1, seconds = 1, minute = 60, minutes = 60, hour = 3600, hours = 3600,
  day = 86400, days = 86400, year = 31536000, years = 31536000,
}

local function clean(s) return (s:gsub("\194\167.", "")) end

-- "10,773,450,724" -> 10773450724; "95.00%" -> 95.0; nil when there's no number.
local function number(s)
  if not s then return nil end
  local digits = s:gsub(",", ""):match("^%s*(%-?%d+%.?%d*)")
  return digits and tonumber(digits) or nil
end

local function split(line)
  local parts = {}
  for p in (clean(line) .. "\\"):gmatch("(.-)\\+") do parts[#parts + 1] = p end
  return parts
end

function lsc.parse(lines)
  local info = { unknown = {} }
  local function first(field, v) if info[field] == nil then info[field] = v end end
  for _, raw in ipairs(lines or {}) do
    local parts = split(tostring(raw))
    local key = (parts[1] or ""):gsub("^kekztech%.infodata%.", ""):gsub("^lapotronic_super_capacitor%.", "")
    local v = parts[2]
    local avg, window = key:match("^avg_eu_(%a+)%.(%w+)$")
    if key == "operational_data" then -- a heading
    elseif key == "eu_stored" then first("stored", number(v))
    elseif key == "total_capacity" then first("capacity", number(v))
    elseif key == "used_capacity" then first("used", number(v))
    elseif key == "passive_loss" then first("passiveLoss", number(v))
    elseif key == "eu_in" then first("inNow", number(v))
    elseif key == "eu_out" then first("outNow", number(v))
    elseif key == "wireless_eu" then first("wirelessEu", number(v))
    elseif avg and (avg == "in" or avg == "out") then
      local field = avg == "in" and "avgIn" or "avgOut"
      info[field] = info[field] or {}
      info[field][window] = number(v)
      if window == "sec" then info[field].window = number(parts[3]) end
    elseif key:find("^time_to%.") then
      local amount, unit = (v or ""):gsub(",", ""):match("^%s*([%d.]+)%s*(%a+)")
      local n = tonumber(amount)
      info.timeTo = { to = key:sub(9), text = v, seconds = n and UNITS[(unit or ""):lower()] and n * UNITS[unit:lower()] }
    elseif key:find("^multi%.maintenance_status%.") then info.maintenance = key:match("([^.]+)$")
    elseif key:find("^wireless_mode%.") then info.wireless = key:match("([^.]+)$")
    elseif key == "capacitors" and parts[2] then
      info.capacitors = info.capacitors or {}
      info.capacitors[parts[2]] = number(parts[3])
    else
      info.unknown[#info.unknown + 1] = raw
    end
  end
  return info
end

return lsc
