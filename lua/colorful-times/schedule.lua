-- lua/colorful-times/schedule.lua
local M = {}

-- Constants
local MINUTES_PER_DAY = 1440

-- Module-level cache for parse_time results (including nil for invalid inputs)
local _parse_time_cache = {}
local _PARSE_TIME_CACHE_LIMIT = 100
local _cache_size = 0

-- Sentinel value to represent cached nil results (since table[key] = nil removes the key in Lua)
local _CACHE_NIL = {}

---@param str string
---@return integer|nil
function M.parse_time(str)
  -- Check cache first using rawget to distinguish "not in cache" from "cached nil"
  local cached = rawget(_parse_time_cache, str)
  if cached ~= nil then
    -- Return nil for cached nil sentinel, otherwise return cached value
    if cached == _CACHE_NIL then
      return nil
    end
    return cached
  end

  local hour, min = str:match("^(%d%d?):(%d%d)$")
  if not hour then
    _parse_time_cache[str] = _CACHE_NIL
    _cache_size = _cache_size + 1
    return nil
  end
  hour, min = tonumber(hour), tonumber(min)
  if hour >= 24 or min >= 60 then
    _parse_time_cache[str] = _CACHE_NIL
    _cache_size = _cache_size + 1
    return nil
  end
  local result = hour * 60 + min
  _parse_time_cache[str] = result
  _cache_size = _cache_size + 1

  -- Limit cache size to prevent unbounded growth
  if _cache_size > _PARSE_TIME_CACHE_LIMIT then
    -- Simple strategy: clear cache when limit exceeded
    _parse_time_cache = {}
    _cache_size = 1
    _parse_time_cache[str] = result
  end

  return result
end

---@param entry table
---@return boolean, string?
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
    return false, "invalid background: " .. entry.background .. " (must be light, dark, or system)"
  end
  return true
end

---@param raw_schedule table
---@param default_background string
---@return ColorfulTimes.ParsedEntry[]
function M.preprocess(raw_schedule, default_background)
  local result = {}
  for idx, slot in ipairs(raw_schedule) do
    local ok, err = M.validate_entry(slot)
    if not ok then
      vim.notify(
        string.format("colorful-times: invalid schedule entry %d: %s", idx, err),
        vim.log.levels.ERROR
      )
    else
      table.insert(result, {
        start_time  = M.parse_time(slot.start),
        stop_time   = M.parse_time(slot.stop),
        colorscheme = slot.colorscheme,
        background  = slot.background or default_background,
      })
    end
  end
  return result
end

---@param parsed ColorfulTimes.ParsedEntry[]
---@param time_mins integer
---@return ColorfulTimes.ParsedEntry|nil
function M.get_active_entry(parsed, time_mins)
  for _, slot in ipairs(parsed) do
    local start_t = slot.start_time
    local stop_t  = slot.stop_time
    local current = time_mins

    if stop_t <= start_t then
      -- overnight: e.g. 22:00 -> 06:00
      if current < start_t then
        current = current + MINUTES_PER_DAY
      end
      stop_t = stop_t + MINUTES_PER_DAY
    end

    if current >= start_t and current < stop_t then
      return slot
    end
  end
  return nil
end

---@param parsed ColorfulTimes.ParsedEntry[]
---@param time_mins integer
---@return integer|nil
function M.next_change_at(parsed, time_mins)
  if #parsed == 0 then
    return nil
  end
  local min_diff = nil

  for i = 1, #parsed do
    local slot = parsed[i]

    -- Check start_time boundary
    local diff_start = slot.start_time - time_mins
    if diff_start <= 0 then
      diff_start = diff_start + MINUTES_PER_DAY
    end
    if not min_diff or diff_start < min_diff then
      min_diff = diff_start
    end

    -- Check stop_time boundary
    local diff_stop = slot.stop_time - time_mins
    if diff_stop <= 0 then
      diff_stop = diff_stop + MINUTES_PER_DAY
    end
    if not min_diff or diff_stop < min_diff then
      min_diff = diff_stop
    end
  end

  return min_diff
end

return M
