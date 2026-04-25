-- lua/colorful-times/schedule.lua
-- Public schedule validation plus runtime schedule helpers.

local runtime = require("colorful-times.schedule_runtime")

local M = {
  parse_time = runtime.parse_time,
  validate_entry = runtime.validate_entry,
  preprocess = runtime.preprocess,
  get_active_entry = runtime.get_active_entry,
  next_change_at = runtime.next_change_at,
}

return M
