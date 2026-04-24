-- lua/colorful-times/tui/actions.lua
-- Mode-aware state transitions and user actions for the TUI.

local M = {}
local ct = require("colorful-times")
local core = require("colorful-times.core")
local schedule = require("colorful-times.schedule")
local ui_state = require("colorful-times.tui.state")
local selectors = require("colorful-times.tui.selectors")
local preview = require("colorful-times.tui.preview")
local view_model = require("colorful-times.tui.view_model")

local function render(app)
  if app.render then
    app.render()
  end
end

local function clamp_cursor(state, rows)
  rows = rows or view_model.sorted_schedule(ct.config.schedule)
  local count = #rows
  state.cursor = math.max(1, math.min(math.max(1, count), state.cursor))
  return rows
end

local function selected_row(state)
  local rows = clamp_cursor(state)
  return rows[state.cursor]
end

local function resolved_draft_background(state)
  if not state.draft then
    return vim.o.background or "dark"
  end
  if state.draft.background == "system" then
    return state.system_background or selectors.resolved_background("system")
  end
  return selectors.resolved_background(state.draft.background)
end

local function apply_draft_preview(state)
  if not state.draft then
    return
  end
  preview.apply(state.draft.colorscheme, state.draft.background, resolved_draft_background(state))
end

local function preview_theme_choice(state, choice)
  if not state.draft or not choice then
    return
  end

  if choice == selectors.fallback_label() then
    state.draft.colorscheme = nil
    if state.selector_snapshot then
      preview.apply(
        state.selector_snapshot.colorscheme,
        state.selector_snapshot.background,
        state.selector_snapshot.resolved_background
      )
    end
    return
  end

  state.draft.colorscheme = choice
  preview.apply(choice, state.draft.background, resolved_draft_background(state))
end

local function save_and_refresh()
  core.save_state()
  if core.refresh then
    core.refresh()
  else
    core.reload()
  end
end

local function default_draft_kind(kind)
  return kind == "default_colorscheme"
    or kind == "default_background"
    or kind == "default_light"
    or kind == "default_dark"
end

local function is_default_draft(state)
  return default_draft_kind(state.draft_kind)
end

local function clear_pending(state)
  state.pending_delete = false
  state.pending_discard = false
  state.message = nil
end

local set_mode_browse

local function draft_dirty(state)
  if not state.draft then
    return false
  end
  if state.draft_kind == "add" then
    return true
  end
  if state.draft_kind ~= "edit" or not state.edit_index then
    return false
  end

  local original = ct.config.schedule and ct.config.schedule[state.edit_index]
  if not original then
    return false
  end

  return state.draft.start ~= original.start
    or state.draft.stop ~= original.stop
    or state.draft.colorscheme ~= original.colorscheme
    or state.draft.background ~= (original.background or ct.config.default.background)
end

local function discard_edit(app)
  preview.restore()
  set_mode_browse(app.state)
  render(app)
end

local function normalize_time(value)
  value = tostring(value or "")
  local hour, minute

  if value:find(":", 1, true) then
    hour, minute = value:match("^(%d%d?):(%d%d?)$")
    if not hour then
      return value
    end
  else
    local digits = value:match("^(%d+)$")
    if not digits then
      return value
    end
    if #digits <= 2 then
      hour, minute = digits, "0"
    elseif #digits == 3 then
      hour, minute = digits:sub(1, 1), digits:sub(2, 3)
    elseif #digits == 4 then
      hour, minute = digits:sub(1, 2), digits:sub(3, 4)
    else
      return value
    end
  end

  hour, minute = tonumber(hour), tonumber(minute)
  if not hour or not minute or hour > 23 or minute > 59 then
    return value
  end
  return string.format("%02d:%02d", hour, minute)
end

local function finish_time_input(state)
  local field = state.time_input_field
  if field and state.draft and (field == "start" or field == "stop") then
    state.draft[field] = normalize_time(state.draft[field])
  end
  state.time_input_field = nil
end

set_mode_browse = function(state)
  ui_state.reset_edit(state)
  clamp_cursor(state)
end

function M.move(app, delta)
  local state = app.state
  clear_pending(state)

  if state.mode == ui_state.modes.browse then
    if state.section == ui_state.sections.defaults then
      ui_state.move_default(state, delta)
    else
      state.cursor = state.cursor + delta
      clamp_cursor(state)
    end
  elseif state.mode == ui_state.modes.edit then
    finish_time_input(state)
    ui_state.move_field(state, delta)
  elseif state.mode == ui_state.modes.theme_select then
    if #state.theme_items > 0 then
      state.theme_cursor = math.max(1, math.min(#state.theme_items, state.theme_cursor + delta))
      preview_theme_choice(state, state.theme_items[state.theme_cursor])
    end
  elseif state.mode == ui_state.modes.bg_select then
    M.cycle_background(app, delta)
    return
  end

  render(app)
end

function M.next_field(app)
  if app.state.mode == ui_state.modes.browse then
    ui_state.toggle_section(app.state)
    render(app)
    return
  end
  if app.state.mode ~= ui_state.modes.edit then
    return
  end
  finish_time_input(app.state)
  ui_state.move_field(app.state, 1)
  render(app)
end

function M.prev_field(app)
  if app.state.mode ~= ui_state.modes.edit then
    return
  end
  finish_time_input(app.state)
  ui_state.move_field(app.state, -1)
  render(app)
end

function M.begin_add(app)
  local state = app.state
  clear_pending(state)
  state.section = ui_state.sections.schedule

  local status = core.status()
  local draft = view_model.add_defaults(ct.config, status)
  preview.begin()

  state.mode = ui_state.modes.edit
  state.draft_kind = "add"
  state.edit_index = nil
  state.field = 1
  state.draft = draft
  state.system_background = status.background or vim.o.background or "dark"
  state.time_input_field = nil

  apply_draft_preview(state)
  render(app)
end

function M.begin_edit(app)
  local state = app.state
  clear_pending(state)

  local row = selected_row(state)
  if not row then
    state.message = "No schedule row selected."
    render(app)
    return
  end

  local status = core.status()
  preview.begin()

  state.mode = ui_state.modes.edit
  state.draft_kind = "edit"
  state.edit_index = row.index
  state.field = 1
  state.draft = vim.deepcopy(row.entry)
  state.draft.background = state.draft.background or ct.config.default.background
  state.system_background = status.background or vim.o.background or "dark"
  state.time_input_field = nil

  apply_draft_preview(state)
  render(app)
end

function M.cancel(app)
  local state = app.state

  if state.pending_discard then
    clear_pending(state)
    render(app)
    return
  end

  if state.mode == ui_state.modes.theme_select or state.mode == ui_state.modes.bg_select then
    if state.selector_snapshot and state.draft then
      state.draft.colorscheme = state.selector_snapshot.colorscheme
      state.draft.background = state.selector_snapshot.background
      preview.apply(
        state.selector_snapshot.colorscheme,
        state.selector_snapshot.background,
        state.selector_snapshot.resolved_background
      )
    end
    state.selector_snapshot = nil
    if is_default_draft(state) then
      preview.restore()
      set_mode_browse(state)
      render(app)
      return
    end
    state.mode = ui_state.modes.edit
    render(app)
    return
  end

  if state.mode == ui_state.modes.edit then
    finish_time_input(state)
    if draft_dirty(state) then
      state.pending_discard = true
      state.message = "Discard unsaved changes? y discard / n or Esc keep editing"
      render(app)
      return
    end
    discard_edit(app)
    return
  end

  if state.pending_delete then
    clear_pending(state)
    render(app)
    return
  end

  if app.close then
    app.close()
  end
end

function M.save(app)
  local state = app.state
  if state.mode ~= ui_state.modes.edit or not state.draft then
    return
  end

  local entry = vim.deepcopy(state.draft)
  entry.start = normalize_time(entry.start)
  entry.stop = normalize_time(entry.stop)
  local ok, err = schedule.validate_entry(entry)
  if not ok then
    state.message = "Cannot save: " .. (err or "invalid entry")
    render(app)
    return
  end

  preview.commit()
  state.draft = entry

  if state.draft_kind == "add" then
    table.insert(ct.config.schedule, entry)
  elseif state.edit_index and ct.config.schedule[state.edit_index] then
    ct.config.schedule[state.edit_index] = entry
  end

  save_and_refresh()
  set_mode_browse(state)
  render(app)
end

function M.enter_theme_select(app)
  local state = app.state
  if state.mode ~= ui_state.modes.edit or not state.draft then
    return
  end

  state.mode = ui_state.modes.theme_select
  state.theme_filter = ""
  state.theme_allow_fallback = false
  state.selector_snapshot = {
    colorscheme = state.draft.colorscheme,
    background = state.draft.background,
    resolved_background = resolved_draft_background(state),
  }
  state.theme_items = selectors.filtered_themes(state.theme_filter, state.draft.colorscheme, false)
  state.theme_cursor = selectors.index_of(state.theme_items, state.draft.colorscheme)

  preview_theme_choice(state, state.theme_items[state.theme_cursor])

  render(app)
end

function M.confirm_theme(app)
  local state = app.state
  if state.mode ~= ui_state.modes.theme_select or not state.draft then
    return
  end

  local choice = state.theme_items[state.theme_cursor]
  if is_default_draft(state) then
    if not choice then
      return
    end

    local selected = choice == selectors.fallback_label() and nil or choice
    local message = nil
    if state.draft_kind == "default_colorscheme" then
      if not selected then
        return
      end
      ct.config.default.colorscheme = selected
      message = "Updated default colorscheme."
    elseif state.draft_kind == "default_light" or state.draft_kind == "default_dark" then
      local key = state.default_key or (state.draft_kind == "default_light" and "light" or "dark")
      ct.config.default.themes[key] = selected
      message = "Updated " .. key .. " theme override."
    end

    preview.commit()
    save_and_refresh()
    set_mode_browse(state)
    state.message = message
    render(app)
    return
  end

  if choice and choice ~= selectors.fallback_label() then
    state.draft.colorscheme = choice
    apply_draft_preview(state)
  end
  state.selector_snapshot = nil
  state.mode = ui_state.modes.edit
  render(app)
end

function M.enter_bg_select(app)
  local state = app.state
  if state.mode ~= ui_state.modes.edit or not state.draft then
    return
  end

  state.mode = ui_state.modes.bg_select
  state.selector_snapshot = {
    colorscheme = state.draft.colorscheme,
    background = state.draft.background,
    resolved_background = resolved_draft_background(state),
  }
  apply_draft_preview(state)
  render(app)
end

local function begin_theme_select(app, kind, current, background, allow_fallback, message_key)
  local state = app.state
  clear_pending(state)

  local status = core.status()
  preview.begin()

  state.mode = ui_state.modes.theme_select
  state.draft_kind = kind
  state.default_key = message_key
  state.field = 3
  state.draft = {
    colorscheme = current,
    background = background or status.requested_background or status.background or vim.o.background or "dark",
  }
  state.system_background = status.background or vim.o.background or "dark"
  state.theme_filter = ""
  state.theme_allow_fallback = allow_fallback or false
  state.selector_snapshot = {
    colorscheme = current,
    background = state.draft.background,
    resolved_background = resolved_draft_background(state),
  }
  state.theme_items = selectors.filtered_themes(state.theme_filter, current, state.theme_allow_fallback)
  state.theme_cursor = selectors.index_of(state.theme_items, current)

  local choice = state.theme_items[state.theme_cursor]
  preview_theme_choice(state, choice)

  render(app)
end

function M.begin_default_colorscheme(app)
  begin_theme_select(
    app,
    "default_colorscheme",
    ct.config.default.colorscheme,
    ct.config.default.background,
    false,
    nil
  )
end

function M.begin_default_background(app)
  local state = app.state
  clear_pending(state)

  local status = core.status()
  preview.begin()

  state.mode = ui_state.modes.bg_select
  state.draft_kind = "default_background"
  state.field = 4
  state.draft = {
    colorscheme = ct.config.default.colorscheme,
    background = ct.config.default.background,
  }
  state.system_background = status.background or vim.o.background or "dark"
  state.selector_snapshot = {
    colorscheme = state.draft.colorscheme,
    background = state.draft.background,
    resolved_background = resolved_draft_background(state),
  }

  apply_draft_preview(state)
  render(app)
end

---@param kind "light"|"dark"
function M.begin_theme_override(app, kind)
  begin_theme_select(
    app,
    kind == "light" and "default_light" or "default_dark",
    ct.config.default.themes[kind],
    kind,
    true,
    kind
  )
end

function M.confirm_bg(app)
  local state = app.state
  if state.mode ~= ui_state.modes.bg_select then
    return
  end

  if is_default_draft(state) and state.draft then
    ct.config.default.background = state.draft.background
    preview.commit()
    save_and_refresh()
    set_mode_browse(state)
    state.message = "Updated default background."
    render(app)
    return
  end

  state.selector_snapshot = nil
  state.mode = ui_state.modes.edit
  render(app)
end

function M.confirm(app)
  local state = app.state

  if state.pending_discard then
    return
  end

  if state.pending_delete then
    return
  end

  if state.mode == ui_state.modes.browse then
    if state.section == ui_state.sections.defaults then
      local field = ui_state.active_default_field(state)
      if field == "colorscheme" then
        M.begin_default_colorscheme(app)
      elseif field == "background" then
        M.begin_default_background(app)
      elseif field == "light" or field == "dark" then
        M.begin_theme_override(app, field)
      end
    else
      M.begin_edit(app)
    end
    return
  end

  if state.mode == ui_state.modes.edit then
    local field = ui_state.active_field(state)
    if field == "colorscheme" then
      M.enter_theme_select(app)
    elseif field == "background" then
      M.enter_bg_select(app)
    end
    return
  end

  if state.mode == ui_state.modes.theme_select then
    M.confirm_theme(app)
  elseif state.mode == ui_state.modes.bg_select then
    M.confirm_bg(app)
  end
end

function M.confirm_prompt(app)
  local state = app.state
  if state.pending_discard then
    discard_edit(app)
    return
  end
  if state.pending_delete then
    M.confirm_delete(app)
  end
end

function M.cycle_background(app, delta)
  local state = app.state
  if not state.draft then
    return
  end

  if state.mode ~= ui_state.modes.edit and state.mode ~= ui_state.modes.bg_select then
    return
  end

  local field = ui_state.active_field(state)
  if state.mode == ui_state.modes.edit and field ~= "background" then
    return
  end

  state.draft.background = selectors.cycle_background(state.draft.background, delta)
  apply_draft_preview(state)
  render(app)
end

function M.input_char(app, char)
  local state = app.state

  if state.mode == ui_state.modes.theme_select then
    state.theme_filter = state.theme_filter .. char
    local current = state.selector_snapshot and state.selector_snapshot.colorscheme or (state.draft and state.draft.colorscheme)
    state.theme_items = selectors.filtered_themes(state.theme_filter, current, state.theme_allow_fallback)
    state.theme_cursor = 1
    preview_theme_choice(state, state.theme_items[state.theme_cursor])
    render(app)
    return
  end

  if state.mode ~= ui_state.modes.edit or not state.draft then
    return
  end

  local field = ui_state.active_field(state)
  if field ~= "start" and field ~= "stop" then
    return
  end

  if not char:match("^[0-9:]$") then
    return
  end

  local value = state.draft[field] or ""
  if state.time_input_field ~= field then
    value = ""
    state.time_input_field = field
  end

  if #value >= 5 then
    return
  end
  state.draft[field] = value .. char
  render(app)
end

function M.backspace(app)
  local state = app.state

  if state.mode == ui_state.modes.theme_select then
    state.theme_filter = state.theme_filter:sub(1, math.max(0, #state.theme_filter - 1))
    local current = state.selector_snapshot and state.selector_snapshot.colorscheme or (state.draft and state.draft.colorscheme)
    state.theme_items = selectors.filtered_themes(state.theme_filter, current, state.theme_allow_fallback)
    state.theme_cursor = 1
    preview_theme_choice(state, state.theme_items[state.theme_cursor])
    render(app)
    return
  end

  if state.mode ~= ui_state.modes.edit or not state.draft then
    return
  end

  local field = ui_state.active_field(state)
  if field == "start" or field == "stop" then
    local value = state.draft[field] or ""
    if state.time_input_field ~= field then
      state.time_input_field = field
    end
    state.draft[field] = value:sub(1, math.max(0, #value - 1))
    render(app)
  end
end

function M.request_delete(app)
  local state = app.state
  if state.mode ~= ui_state.modes.browse or state.section ~= ui_state.sections.schedule then
    return
  end

  local row = selected_row(state)
  if not row then
    state.message = "No schedule row selected."
    render(app)
    return
  end

  local entry = row.entry
  state.pending_delete = true
  state.message =
    string.format("Delete %s-%s %s? y delete / n or Esc cancel", entry.start, entry.stop, entry.colorscheme)
  render(app)
end

function M.confirm_delete(app)
  local state = app.state
  if not state.pending_delete then
    return
  end

  local row = selected_row(state)
  if row then
    table.remove(ct.config.schedule, row.index)
    save_and_refresh()
  end
  clear_pending(state)
  clamp_cursor(state)
  render(app)
end

function M.toggle_hold(app)
  local state = app.state
  if core.status().pinned then
    core.unpin_session()
    state.message = "Session hold released."
    render(app)
    return
  end

  if state.draft then
    core.pin_session(state.draft.colorscheme, state.draft.background, resolved_draft_background(state))
    preview.commit()
    set_mode_browse(state)
    state.message = "Held draft preview for this session."
    render(app)
    return
  end

  local status = core.status()
  core.pin_session(status.colorscheme, status.requested_background, status.background)
  state.message = "Held current theme for this session."
  render(app)
end

function M.pin_browse(app)
  M.toggle_hold(app)
end

function M.pin_draft(app)
  M.toggle_hold(app)
end

function M.unpin(app)
  core.unpin_session()
  app.state.message = "Session hold released."
  render(app)
end

function M.toggle(app)
  if app.state.mode ~= ui_state.modes.browse then
    return
  end
  clear_pending(app.state)
  core.toggle()
  render(app)
end

function M.reload(app)
  if app.state.mode ~= ui_state.modes.browse then
    return
  end
  clear_pending(app.state)
  core.reload()
  app.state.system_background = core.status().background
  app.state.message = "Reloaded configuration."
  render(app)
end

function M.help()
  vim.notify(
    table.concat({
      "colorful-times keys:",
      "  browse: Tab switches Defaults/Schedule, j/k move, Enter edit, a add schedule, d delete schedule, H hold/release session theme, q close",
      "  edit: Tab/j/k fields, type 0-9/: replaces active time, h/l cycles background on bg field, O session hold, S save, Esc cancel",
      "  theme selector: type filter, Backspace erase, j/k move, Enter choose, Esc cancel",
    }, "\n"),
    vim.log.levels.INFO
  )
end

function M.left(app)
  local state = app.state
  if state.mode == ui_state.modes.edit then
    finish_time_input(state)
    if ui_state.active_field(state) == "background" then
      M.cycle_background(app, -1)
    end
    return
  end

  M.cycle_background(app, -1)
end

function M.right(app)
  local state = app.state
  if state.mode == ui_state.modes.edit then
    finish_time_input(state)
    if ui_state.active_field(state) == "background" then
      M.cycle_background(app, 1)
    end
    return
  end

  M.cycle_background(app, 1)
end

function M.close_or_cancel(app)
  if app.state.mode == ui_state.modes.browse and not app.state.pending_delete then
    if app.close then
      app.close()
    end
    return
  end
  M.cancel(app)
end

return M
