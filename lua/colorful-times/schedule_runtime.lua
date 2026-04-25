-- lua/colorful-times/schedule_runtime.lua
-- Internal schedule parsing and lookup helpers used by first-apply hot paths.

local M = {}

local MINUTES_PER_DAY = 1440
local VALID_BACKGROUNDS = { light = true, dark = true, system = true }

local _time_cache = {}
local _CACHE_NIL = {}

local _next_change_cache_entry = nil
local _next_change_cache_time = nil
local _next_change_cache_result = nil

---@param str unknown
---@return integer|nil
function M.parse_time(str)
  if type(str) ~= "string" then
    return nil
  end

  local cached = _time_cache[str]
  if cached ~= nil then
    if cached == _CACHE_NIL then return nil end
    return cached
  end

  local hour, min = str:match("^(%d%d?):(%d%d)$")
  if not hour then
    _time_cache[str] = _CACHE_NIL
    return nil
  end

  hour, min = tonumber(hour), tonumber(min)
  if hour >= 24 or min >= 60 then
    _time_cache[str] = _CACHE_NIL
    return nil
  end

  local result = hour * 60 + min
  _time_cache[str] = result
  return result
end

local function validate_slot(slot)
  if type(slot) ~= "table" then
    return false, "entry must be a table"
  end

  if type(slot.colorscheme) ~= "string" or slot.colorscheme == "" then
    return false, "missing colorscheme"
  end

  local start_time = M.parse_time(slot.start)
  if type(slot.start) ~= "string" or not start_time then
    return false, "invalid start time: " .. tostring(slot.start)
  end

  local stop_time = M.parse_time(slot.stop)
  if type(slot.stop) ~= "string" or not stop_time then
    return false, "invalid stop time: " .. tostring(slot.stop)
  end

  if start_time == stop_time then
    return false, "start and stop times must differ: " .. tostring(slot.start)
  end

  if slot.background ~= nil then
    if type(slot.background) ~= "string" or not VALID_BACKGROUNDS[slot.background] then
      return false, "invalid background: " .. tostring(slot.background)
    end
  end

  return true, nil, start_time, stop_time
end

---@param raw unknown
---@param default_bg string
---@return ColorfulTimes.ParsedEntry[]
function M.preprocess(raw, default_bg)
  if type(raw) ~= "table" then
    return {}
  end

  local result = {}
  local boundaries_set = {}

  for idx, slot in ipairs(raw) do
    local ok, err, start_time, stop_time = validate_slot(slot)
    if not ok then
      vim.notify(string.format("colorful-times: invalid entry %d: %s", idx, err), vim.log.levels.ERROR)
    else
      table.insert(result, {
        start_time = start_time,
        stop_time = stop_time,
        colorscheme = slot.colorscheme,
        background = slot.background or default_bg,
      })
      boundaries_set[start_time] = true
      boundaries_set[stop_time] = true
    end
  end

  if #result > 0 then
    local boundaries = {}
    for t in pairs(boundaries_set) do
      table.insert(boundaries, t)
    end
    table.sort(boundaries)
    result._boundaries = boundaries
  end

  return result
end

local function is_active(entry, time_mins)
  local start_t, stop_t, current = entry.start_time, entry.stop_time, time_mins

  if stop_t <= start_t then
    if current < start_t then current = current + MINUTES_PER_DAY end
    stop_t = stop_t + MINUTES_PER_DAY
  end

  return current >= start_t and current < stop_t
end

---@param parsed ColorfulTimes.ParsedEntry[]
---@param time_mins integer
---@return ColorfulTimes.ParsedEntry|nil
function M.get_active_entry(parsed, time_mins)
  for _, entry in ipairs(parsed) do
    if is_active(entry, time_mins) then
      return entry
    end
  end
  return nil
end

---@param parsed ColorfulTimes.ParsedEntry[]
---@param time_mins integer
---@return integer|nil
function M.next_change_at(parsed, time_mins)
  if #parsed == 0 then return nil end

  if _next_change_cache_entry == parsed and _next_change_cache_time == time_mins then
    return _next_change_cache_result
  end

  local boundaries = parsed._boundaries
  if not boundaries then
    local min_diff
    for _, entry in ipairs(parsed) do
      local diff1 = entry.start_time - time_mins
      if diff1 <= 0 then
        diff1 = diff1 + MINUTES_PER_DAY
      end
      min_diff = math.min(min_diff or diff1, diff1)

      local diff2 = entry.stop_time - time_mins
      if diff2 <= 0 then
        diff2 = diff2 + MINUTES_PER_DAY
      end
      min_diff = math.min(min_diff or diff2, diff2)
    end
    return min_diff
  end

  local lo, hi = 1, #boundaries
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if boundaries[mid] <= time_mins then
      lo = mid + 1
    else
      hi = mid - 1
    end
  end

  local min_diff
  if lo <= #boundaries then
    min_diff = boundaries[lo] - time_mins
  else
    min_diff = (boundaries[1] + MINUTES_PER_DAY) - time_mins
  end

  _next_change_cache_entry = parsed
  _next_change_cache_time = time_mins
  _next_change_cache_result = min_diff

  return min_diff
end

return M
