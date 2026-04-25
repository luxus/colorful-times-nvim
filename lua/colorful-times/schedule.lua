-- lua/colorful-times/schedule.lua
-- Public schedule validation plus runtime schedule helpers.

local runtime = require("colorful-times.schedule_runtime")

local M = {
  parse_time = runtime.parse_time,
  preprocess = runtime.preprocess,
  get_active_entry = runtime.get_active_entry,
  next_change_at = runtime.next_change_at,
}

-- Static lookup for valid backgrounds
local VALID_BACKGROUNDS = { light = true, dark = true, system = true }

---Validate a schedule entry
---@param entry unknown
---@return boolean ok
---@return string? error
function M.validate_entry(entry)
  if type(entry) ~= "table" then
    return false, "entry must be a table"
  end

  if type(entry.colorscheme) ~= "string" or entry.colorscheme == "" then
    return false, "missing colorscheme"
  end

  if type(entry.start) ~= "string" or not M.parse_time(entry.start) then
    return false, "invalid start time: " .. tostring(entry.start)
  end

  if type(entry.stop) ~= "string" or not M.parse_time(entry.stop) then
    return false, "invalid stop time: " .. tostring(entry.stop)
  end

  if M.parse_time(entry.start) == M.parse_time(entry.stop) then
    return false, "start and stop times must differ: " .. tostring(entry.start)
  end

  if entry.background ~= nil then
    if type(entry.background) ~= "string" or not VALID_BACKGROUNDS[entry.background] then
      return false, "invalid background: " .. tostring(entry.background)
    end
  end

  return true
end

return M
