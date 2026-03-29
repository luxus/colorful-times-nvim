-- lua/colorful-times/schedule.lua
-- Streamlined schedule parsing with vim.iter patterns

local M = {}

local MINUTES_PER_DAY = 1440

-- Simple LRU cache for parse_time (max 100 entries)
local _time_cache = {}
local _time_cache_order = {}
local _CACHE_LIMIT = 100
local _CACHE_NIL = {}  -- Sentinel for cached nil values

---Parse HH:MM time string to minutes since midnight
---@param str string
---@return integer|nil
function M.parse_time(str)
  -- Check cache using rawget to distinguish nil from not-cached
  local cached = rawget(_time_cache, str)
  if cached ~= nil then
    if cached == _CACHE_NIL then return nil end
    return cached
  end
  
  local hour, min = str:match("^(%d%d?):(%d%d)$")
  if not hour then
    _time_cache[str] = _CACHE_NIL
    table.insert(_time_cache_order, str)
    return nil
  end
  
  hour, min = tonumber(hour), tonumber(min)
  if hour >= 24 or min >= 60 then
    _time_cache[str] = _CACHE_NIL
    table.insert(_time_cache_order, str)
    return nil
  end
  
  local result = hour * 60 + min
  
  -- Simple cache management: clear when limit reached
  if #_time_cache_order >= _CACHE_LIMIT then
    _time_cache = {}
    _time_cache_order = {}
  end
  
  _time_cache[str] = result
  table.insert(_time_cache_order, str)
  
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
  if entry.background and not vim.tbl_contains({ "light", "dark", "system" }, entry.background) then
    return false, "invalid background: " .. entry.background
  end
  return true
end

---Preprocess raw schedule into parsed entries
---@param raw table[]
---@param default_bg string
---@return ColorfulTimes.ParsedEntry[]
function M.preprocess(raw, default_bg)
  local result = {}
  for idx, slot in ipairs(raw) do
    local ok, err = M.validate_entry(slot)
    if not ok then
      vim.notify(string.format("colorful-times: invalid entry %d: %s", idx, err), vim.log.levels.ERROR)
    else
      table.insert(result, {
        start_time = M.parse_time(slot.start),
        stop_time = M.parse_time(slot.stop),
        colorscheme = slot.colorscheme,
        background = slot.background or default_bg,
      })
    end
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
---@param parsed ColorfulTimes.ParsedEntry[]
---@param time_mins integer
---@return integer|nil
function M.next_change_at(parsed, time_mins)
  if #parsed == 0 then return nil end
  
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

return M
