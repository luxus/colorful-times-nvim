-- lua/colorful-times/schedule.lua
-- Streamlined schedule parsing with vim.iter patterns

local M = {}

local MINUTES_PER_DAY = 1440

-- Optimized LRU cache for parse_time (max 50 entries - time strings are limited)
local _time_cache = {}
local _CACHE_LIMIT = 50
local _CACHE_NIL = {}  -- Sentinel for cached nil values

-- Static lookup for valid backgrounds
local VALID_BACKGROUNDS = { light = true, dark = true, system = true }

-- Cache for next_change_at to avoid recomputation
local _next_change_cache_entry = nil
local _next_change_cache_time = nil
local _next_change_cache_result = nil

---Parse HH:MM time string to minutes since midnight
---@param str string
---@return integer|nil
function M.parse_time(str)
  -- Fast path: check cache first (handles both hits and nil-sentinel misses)
  local cached = _time_cache[str]
  if cached ~= nil then
    if cached == _CACHE_NIL then return nil end
    return cached
  end
  
  -- Parse the time string
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
  
  -- LRU eviction: only remove oldest when at limit (rare for time strings)
  -- Time strings have max 1440 unique values (24h * 60m), but typically <10 used
  local cache_size = 0
  for _ in pairs(_time_cache) do cache_size = cache_size + 1 end
  if cache_size >= _CACHE_LIMIT then
    -- Find and remove first entry (oldest in insertion order)
    for k in pairs(_time_cache) do
      _time_cache[k] = nil
      break
    end
  end
  
  _time_cache[str] = result
  return result
end

---Validate a schedule entry
---@param entry table
---@return boolean ok
---@return string? error
function M.validate_entry(entry)
  if not entry.colorscheme or entry.colorscheme == "" then
    return false, "missing colorscheme"
  end
  if not M.parse_time(entry.start or "") then
    return false, "invalid start time: " .. tostring(entry.start)
  end
  if not M.parse_time(entry.stop or "") then
    return false, "invalid stop time: " .. tostring(entry.stop)
  end
  if M.parse_time(entry.start) == M.parse_time(entry.stop) then
    return false, "start and stop times must differ: " .. tostring(entry.start)
  end
  if entry.background and not VALID_BACKGROUNDS[entry.background] then
    return false, "invalid background: " .. entry.background
  end
  return true
end

---Preprocess raw schedule into parsed entries with optimized boundary table
---@param raw table[]
---@param default_bg string
---@return ColorfulTimes.ParsedEntry[]
function M.preprocess(raw, default_bg)
  local result = {}
  local boundaries_set = {}  -- For deduplication
  
  for idx, slot in ipairs(raw) do
    local ok, err = M.validate_entry(slot)
    if not ok then
      vim.notify(string.format("colorful-times: invalid entry %d: %s", idx, err), vim.log.levels.ERROR)
    else
      local start_time = M.parse_time(slot.start)
      local stop_time = M.parse_time(slot.stop)
      table.insert(result, {
        start_time = start_time,
        stop_time = stop_time,
        colorscheme = slot.colorscheme,
        background = slot.background or default_bg,
      })
      -- Collect unique boundaries
      boundaries_set[start_time] = true
      boundaries_set[stop_time] = true
    end
  end
  
  -- Build sorted boundary table for O(log n) lookup
  if #result > 0 then
    local boundaries = {}
    for t in pairs(boundaries_set) do
      table.insert(boundaries, t)
    end
    table.sort(boundaries)
    -- Store on result table (non-numeric key won't affect ipairs)
    result._boundaries = boundaries
  end
  
  return result
end

---Check if current time is within an entry's time range
---@param entry ColorfulTimes.ParsedEntry
---@param time_mins integer
---@return boolean
local function is_active(entry, time_mins)
  local start_t, stop_t, current = entry.start_time, entry.stop_time, time_mins
  
  if stop_t <= start_t then
    -- Overnight span (e.g., 22:00 -> 06:00)
    if current < start_t then current = current + MINUTES_PER_DAY end
    stop_t = stop_t + MINUTES_PER_DAY
  end
  
  return current >= start_t and current < stop_t
end

---Get the currently active schedule entry from parsed entries
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

---Get the currently active schedule entry from raw entries (convenience)
---@param raw table[]
---@param time_mins integer
---@param default_bg string
---@return ColorfulTimes.ParsedEntry|nil
function M.get_active(raw, time_mins, default_bg)
  return M.get_active_entry(M.preprocess(raw, default_bg), time_mins)
end

---Calculate minutes until next schedule boundary
---Uses binary search on precomputed boundary table for O(log n) performance
---@param parsed ColorfulTimes.ParsedEntry[]
---@param time_mins integer
---@return integer|nil
function M.next_change_at(parsed, time_mins)
  if #parsed == 0 then return nil end
  
  -- Use cache if same parsed schedule and time_mins matches cached value
  if _next_change_cache_entry == parsed and _next_change_cache_time == time_mins then
    return _next_change_cache_result
  end
  
  local boundaries = parsed._boundaries
  if not boundaries then
    -- Fallback to O(n) method if boundaries not precomputed (shouldn't happen)
    local min_diff
    for _, entry in ipairs(parsed) do
      for _, boundary in ipairs({ entry.start_time, entry.stop_time }) do
        local diff = boundary - time_mins
        if diff <= 0 then diff = diff + MINUTES_PER_DAY end
        min_diff = math.min(min_diff or diff, diff)
      end
    end
    return min_diff
  end
  
  -- Binary search to find first boundary > time_mins
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
    -- Wrap around to first boundary of next day
    min_diff = (boundaries[1] + MINUTES_PER_DAY) - time_mins
  end
  
  -- Simple single-entry cache with replacement strategy
  _next_change_cache_entry = parsed
  _next_change_cache_time = time_mins
  _next_change_cache_result = min_diff
  
  return min_diff
end

return M
