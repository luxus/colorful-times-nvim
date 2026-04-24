-- lua/colorful-times/tui/view_model.lua
-- Pure-ish projections from plugin config/runtime state to renderable TUI data.

local M = {}
local schedule = require("colorful-times.schedule")

local MINUTES_PER_DAY = 1440

---@param value? string
---@return string
function M.display_theme(value)
  return value and value ~= "" and value or "(fallback)"
end

---@param value? string
---@return string
function M.display_cell(value)
  return value and value ~= "" and value or "—"
end

---@param value? string
---@param width integer
---@return string
function M.pad(value, width)
  local text = tostring(value or "")
  local display_width = vim.fn.strdisplaywidth(text)
  if display_width >= width then
    return text:sub(1, math.max(1, width - 1)) .. " "
  end
  return text .. string.rep(" ", width - display_width)
end

---@return integer
function M.now_mins()
  local t = os.date("*t")
  return t.hour * 60 + t.min
end

---@param mins integer
---@return string
function M.format_time(mins)
  mins = mins % MINUTES_PER_DAY
  return string.format("%02d:%02d", math.floor(mins / 60), mins % 60)
end

---@param entry ColorfulTimes.ScheduleEntry
---@param time_mins integer
---@return boolean
local function entry_active(entry, time_mins)
  local start_time = schedule.parse_time(entry.start)
  local stop_time = schedule.parse_time(entry.stop)
  if not start_time or not stop_time then
    return false
  end

  local current = time_mins
  if stop_time <= start_time then
    if current < start_time then
      current = current + MINUTES_PER_DAY
    end
    stop_time = stop_time + MINUTES_PER_DAY
  end

  return current >= start_time and current < stop_time
end

---@param raw ColorfulTimes.ScheduleEntry[]
---@return table[]
function M.sorted_schedule(raw)
  local rows = {}
  for index, entry in ipairs(raw or {}) do
    rows[#rows + 1] = {
      index = index,
      entry = entry,
      start_time = schedule.parse_time(entry.start) or 0,
    }
  end

  table.sort(rows, function(a, b)
    if a.start_time == b.start_time then
      return a.index < b.index
    end
    return a.start_time < b.start_time
  end)

  return rows
end

---@param raw ColorfulTimes.ScheduleEntry[]
---@param cursor integer
---@return table|nil
function M.selected_row(raw, cursor)
  local rows = M.sorted_schedule(raw)
  return rows[cursor]
end

---@param config ColorfulTimes.Config
---@param status ColorfulTimes.Status
---@return ColorfulTimes.ScheduleEntry
function M.add_defaults(config, status)
  local rows = M.sorted_schedule(config.schedule)
  local start = "08:00"
  local stop = "18:00"

  if #rows > 0 then
    start = rows[#rows].entry.stop
    stop = rows[1].entry.start
  end

  return {
    start = start,
    stop = stop,
    colorscheme = status.colorscheme or vim.g.colors_name or config.default.colorscheme,
    background = status.background or vim.o.background or config.default.background,
  }
end

---@param config ColorfulTimes.Config
---@param status ColorfulTimes.Status
---@param ui_state ColorfulTimes.TuiState
---@return table
function M.build(config, status, ui_state)
  local now = M.now_mins()
  local rows = M.sorted_schedule(config.schedule)

  for _, row in ipairs(rows) do
    row.active = entry_active(row.entry, now)
  end

  return {
    enabled = config.enabled,
    default = config.default,
    rows = rows,
    row_count = #rows,
    now = now,
    now_label = M.format_time(now),
    status = status,
    ui = ui_state,
  }
end

return M
