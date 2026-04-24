-- lua/colorful-times/tui/state.lua
-- Ephemeral state for the Colorful Times floating TUI.

local M = {}

M.modes = {
  browse = "browse",
  edit = "edit",
  theme_select = "theme_select",
  bg_select = "bg_select",
}

M.fields = { "start", "stop", "colorscheme", "background" }
M.sections = { defaults = "defaults", schedule = "schedule" }
M.default_fields = { "colorscheme", "background", "light", "dark" }

---@class ColorfulTimes.TuiState
---@field mode "browse"|"edit"|"theme_select"|"bg_select"
---@field cursor integer Display-order schedule cursor.
---@field section "defaults"|"schedule" Active browse section.
---@field default_cursor integer Active default row cursor.
---@field field integer Active edit field index.
---@field draft ColorfulTimes.ScheduleEntry|nil
---@field draft_kind "add"|"edit"|"default_colorscheme"|"default_background"|"default_light"|"default_dark"|nil
---@field edit_index integer|nil Original schedule index for edit mode.
---@field default_key "light"|"dark"|nil
---@field time_input_field "start"|"stop"|nil Field whose time text is being replaced.
---@field theme_filter string
---@field theme_cursor integer
---@field theme_items string[]
---@field theme_allow_fallback boolean
---@field selector_snapshot table|nil
---@field system_background string
---@field pending_delete boolean
---@field pending_discard boolean
---@field message string|nil

---@return ColorfulTimes.TuiState
function M.new()
  return {
    mode = M.modes.browse,
    cursor = 1,
    section = M.sections.schedule,
    default_cursor = 1,
    field = 1,
    draft = nil,
    draft_kind = nil,
    edit_index = nil,
    default_key = nil,
    time_input_field = nil,
    theme_filter = "",
    theme_cursor = 1,
    theme_items = {},
    theme_allow_fallback = false,
    selector_snapshot = nil,
    system_background = vim.o.background or "dark",
    pending_delete = false,
    pending_discard = false,
    message = nil,
  }
end

---@param state ColorfulTimes.TuiState
function M.toggle_section(state)
  state.section = state.section == M.sections.defaults and M.sections.schedule or M.sections.defaults
end

---@param state ColorfulTimes.TuiState
---@param delta integer
function M.move_default(state, delta)
  state.default_cursor = math.max(1, math.min(#M.default_fields, state.default_cursor + delta))
end

---@param state ColorfulTimes.TuiState
---@return string
function M.active_default_field(state)
  return M.default_fields[state.default_cursor] or M.default_fields[1]
end

---@param state ColorfulTimes.TuiState
---@return boolean
function M.in_defaults(state)
  return state.mode == M.modes.browse and state.section == M.sections.defaults
end

---@param state ColorfulTimes.TuiState
function M.reset_edit(state)
  state.mode = M.modes.browse
  state.field = 1
  state.draft = nil
  state.draft_kind = nil
  state.edit_index = nil
  state.default_key = nil
  state.time_input_field = nil
  state.theme_filter = ""
  state.theme_cursor = 1
  state.theme_items = {}
  state.theme_allow_fallback = false
  state.selector_snapshot = nil
  state.pending_delete = false
  state.pending_discard = false
  state.message = nil
end

---@param state ColorfulTimes.TuiState
---@return string
function M.active_field(state)
  return M.fields[state.field] or M.fields[1]
end

---@param state ColorfulTimes.TuiState
---@param delta integer
function M.move_field(state, delta)
  local before = state.field
  state.field = math.max(1, math.min(#M.fields, state.field + delta))
  if state.field ~= before then
    state.time_input_field = nil
  end
end

return M
