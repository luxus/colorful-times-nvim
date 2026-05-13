-- lua/colorful-times/tui/action_policy.lua
-- TUI state machine. Mutates TUI/config state and returns effect intents.

local M = {}
local H = {}
local schedule = require("colorful-times.schedule_runtime")
local ui_state = require("colorful-times.tui.state")
local selectors = require("colorful-times.tui.selectors")
local view_model = require("colorful-times.tui.view_model")

local CURRENT

local function emit(ctx, kind, data)
  data = data or {}
  data.kind = kind
  ctx.effects[#ctx.effects + 1] = data
end

local function emit_preview_apply(target)
  emit(CURRENT, "preview_apply", { target = target })
end

local function emit_pin_session(colorscheme, background, resolved_background)
  emit(CURRENT, "pin_session", { colorscheme = colorscheme, background = background, resolved_background = resolved_background })
end

local function clamp_cursor(state, rows)
  rows = rows or view_model.sorted_schedule(CURRENT.config.schedule)
  local count = #rows
  state.cursor = math.max(1, math.min(math.max(1, count), state.cursor))
  return rows
end

local function selected_row(state)
  local rows = clamp_cursor(state)
  return rows[state.cursor]
end

local function preview_target(state)
  return CURRENT.preview_target({
    draft = state.draft,
    draft_kind = state.draft_kind,
    known_resolved_background = state.system_background or CURRENT.current_background or "dark",
  })
end

local function resolved_draft_background(state)
  return preview_target(state).resolved_background
end

local function apply_draft_preview(state)
  if not state.draft then
    return
  end
  emit_preview_apply(preview_target(state))
end

local function preview_theme_choice(state, choice)
  if not state.draft or not choice then
    return
  end

  if choice == selectors.fallback_label() then
    state.draft.colorscheme = nil
    if state.selector_snapshot then
      emit_preview_apply({
        colorscheme = state.selector_snapshot.colorscheme,
        requested_background = state.selector_snapshot.background,
        resolved_background = state.selector_snapshot.resolved_background,
      })
    end
    return
  end

  state.draft.colorscheme = choice
  apply_draft_preview(state)
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

  local original = CURRENT.config.schedule and CURRENT.config.schedule[state.edit_index]
  if not original then
    return false
  end

  return state.draft.start ~= original.start
    or state.draft.stop ~= original.stop
    or state.draft.colorscheme ~= original.colorscheme
    or state.draft.background ~= (original.background or CURRENT.config.default.background)
end

local function discard_edit(ctx)
  emit(ctx, "preview_restore")
  set_mode_browse(ctx.state)
  emit(ctx, "render")
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

function H.move(ctx, delta)
  local state = ctx.state
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
    H.cycle_background(ctx, delta)
    return
  end

  emit(ctx, "render")
end

function H.next_field(ctx)
  if ctx.state.mode == ui_state.modes.browse then
    ui_state.toggle_section(ctx.state)
    emit(ctx, "render")
    return
  end
  if ctx.state.mode ~= ui_state.modes.edit then
    return
  end
  finish_time_input(ctx.state)
  ui_state.move_field(ctx.state, 1)
  emit(ctx, "render")
end

function H.prev_field(ctx)
  if ctx.state.mode ~= ui_state.modes.edit then
    return
  end
  finish_time_input(ctx.state)
  ui_state.move_field(ctx.state, -1)
  emit(ctx, "render")
end

function H.begin_add(ctx)
  local state = ctx.state
  clear_pending(state)
  state.section = ui_state.sections.schedule

  local status = ctx.status()
  local draft = view_model.add_defaults(ctx.config, status)
  emit(ctx, "preview_begin")

  state.mode = ui_state.modes.edit
  state.draft_kind = "add"
  state.edit_index = nil
  state.field = 1
  state.draft = draft
  state.system_background = status.background or ctx.current_background or "dark"
  state.time_input_field = nil

  apply_draft_preview(state)
  emit(ctx, "render")
end

function H.begin_edit(ctx)
  local state = ctx.state
  clear_pending(state)

  local row = selected_row(state)
  if not row then
    state.message = "No schedule row selected."
    emit(ctx, "render")
    return
  end

  local status = ctx.status()
  emit(ctx, "preview_begin")

  state.mode = ui_state.modes.edit
  state.draft_kind = "edit"
  state.edit_index = row.index
  state.field = 1
  state.draft = vim.deepcopy(row.entry)
  state.draft.background = state.draft.background or ctx.config.default.background
  state.system_background = status.background or ctx.current_background or "dark"
  state.time_input_field = nil

  apply_draft_preview(state)
  emit(ctx, "render")
end

function H.cancel(ctx)
  local state = ctx.state

  if state.pending_discard then
    clear_pending(state)
    emit(ctx, "render")
    return
  end

  if state.mode == ui_state.modes.theme_select or state.mode == ui_state.modes.bg_select then
    if state.selector_snapshot and state.draft then
      state.draft.colorscheme = state.selector_snapshot.colorscheme
      state.draft.background = state.selector_snapshot.background
      emit_preview_apply({
        colorscheme = state.selector_snapshot.colorscheme,
        requested_background = state.selector_snapshot.background,
        resolved_background = state.selector_snapshot.resolved_background,
      })
    end
    state.selector_snapshot = nil
    if is_default_draft(state) then
      emit(ctx, "preview_restore")
      set_mode_browse(state)
      emit(ctx, "render")
      return
    end
    state.mode = ui_state.modes.edit
    emit(ctx, "render")
    return
  end

  if state.mode == ui_state.modes.edit then
    finish_time_input(state)
    if draft_dirty(state) then
      state.pending_discard = true
      state.message = "Discard unsaved changes? y discard / n or Esc keep editing"
      emit(ctx, "render")
      return
    end
    discard_edit(ctx)
    return
  end

  if state.pending_delete then
    clear_pending(state)
    emit(ctx, "render")
    return
  end

  if ctx.close then
    ctx.close()
  end
end

function H.save(ctx)
  local state = ctx.state
  if state.mode ~= ui_state.modes.edit or not state.draft then
    return
  end

  local entry = vim.deepcopy(state.draft)
  entry.start = normalize_time(entry.start)
  entry.stop = normalize_time(entry.stop)
  local ok, err = schedule.validate_entry(entry)
  if not ok then
    state.message = "Cannot save: " .. (err or "invalid entry")
    emit(ctx, "render")
    return
  end

  emit(ctx, "preview_commit")
  state.draft = entry

  if state.draft_kind == "add" then
    table.insert(ctx.config.schedule, entry)
  elseif state.edit_index and ctx.config.schedule[state.edit_index] then
    ctx.config.schedule[state.edit_index] = entry
  end

  emit(ctx, "save_refresh")
  set_mode_browse(state)
  emit(ctx, "render")
end

function H.enter_theme_select(ctx)
  local state = ctx.state
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

  emit(ctx, "render")
end

function H.confirm_theme(ctx)
  local state = ctx.state
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
      ctx.config.default.colorscheme = selected
      message = "Updated default colorscheme."
    elseif state.draft_kind == "default_light" or state.draft_kind == "default_dark" then
      local key = state.default_key or (state.draft_kind == "default_light" and "light" or "dark")
      ctx.config.default.themes[key] = selected
      message = "Updated " .. key .. " theme override."
    end

    emit(ctx, "preview_commit")
    emit(ctx, "save_refresh")
    set_mode_browse(state)
    state.message = message
    emit(ctx, "render")
    return
  end

  if choice and choice ~= selectors.fallback_label() then
    state.draft.colorscheme = choice
    apply_draft_preview(state)
  end
  state.selector_snapshot = nil
  state.mode = ui_state.modes.edit
  emit(ctx, "render")
end

function H.enter_bg_select(ctx)
  local state = ctx.state
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
  emit(ctx, "render")
end

local function begin_theme_select(ctx, kind, current, background, allow_fallback, message_key)
  local state = ctx.state
  clear_pending(state)

  local status = ctx.status()
  emit(ctx, "preview_begin")

  state.mode = ui_state.modes.theme_select
  state.draft_kind = kind
  state.default_key = message_key
  state.field = 3
  state.draft = {
    colorscheme = current,
    background = background or status.requested_background or status.background or ctx.current_background or "dark",
  }
  state.system_background = status.background or ctx.current_background or "dark"
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

  emit(ctx, "render")
end

function H.begin_default_colorscheme(ctx)
  begin_theme_select(
    ctx,
    "default_colorscheme",
    ctx.config.default.colorscheme,
    ctx.config.default.background,
    false,
    nil
  )
end

function H.begin_default_background(ctx)
  local state = ctx.state
  clear_pending(state)

  local status = ctx.status()
  emit(ctx, "preview_begin")

  state.mode = ui_state.modes.bg_select
  state.draft_kind = "default_background"
  state.field = 4
  state.draft = {
    colorscheme = ctx.config.default.colorscheme,
    background = ctx.config.default.background,
  }
  state.system_background = status.background or ctx.current_background or "dark"
  state.selector_snapshot = {
    colorscheme = state.draft.colorscheme,
    background = state.draft.background,
    resolved_background = resolved_draft_background(state),
  }

  apply_draft_preview(state)
  emit(ctx, "render")
end

---@param kind "light"|"dark"
function H.begin_theme_override(ctx, kind)
  begin_theme_select(
    ctx,
    kind == "light" and "default_light" or "default_dark",
    ctx.config.default.themes[kind],
    kind,
    true,
    kind
  )
end

function H.confirm_bg(ctx)
  local state = ctx.state
  if state.mode ~= ui_state.modes.bg_select then
    return
  end

  if is_default_draft(state) and state.draft then
    ctx.config.default.background = state.draft.background
    emit(ctx, "preview_commit")
    emit(ctx, "save_refresh")
    set_mode_browse(state)
    state.message = "Updated default background."
    emit(ctx, "render")
    return
  end

  state.selector_snapshot = nil
  state.mode = ui_state.modes.edit
  emit(ctx, "render")
end

function H.confirm(ctx)
  local state = ctx.state

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
        H.begin_default_colorscheme(ctx)
      elseif field == "background" then
        H.begin_default_background(ctx)
      elseif field == "light" or field == "dark" then
        H.begin_theme_override(ctx, field)
      end
    else
      H.begin_edit(ctx)
    end
    return
  end

  if state.mode == ui_state.modes.edit then
    local field = ui_state.active_field(state)
    if field == "colorscheme" then
      H.enter_theme_select(ctx)
    elseif field == "background" then
      H.enter_bg_select(ctx)
    end
    return
  end

  if state.mode == ui_state.modes.theme_select then
    H.confirm_theme(ctx)
  elseif state.mode == ui_state.modes.bg_select then
    H.confirm_bg(ctx)
  end
end

function H.confirm_prompt(ctx)
  local state = ctx.state
  if state.pending_discard then
    discard_edit(ctx)
    return
  end
  if state.pending_delete then
    H.confirm_delete(ctx)
  end
end

function H.cycle_background(ctx, delta)
  local state = ctx.state
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
  emit(ctx, "render")
end

function H.input_char(ctx, char)
  local state = ctx.state

  if state.mode == ui_state.modes.theme_select then
    state.theme_filter = state.theme_filter .. char
    local current = state.selector_snapshot and state.selector_snapshot.colorscheme or (state.draft and state.draft.colorscheme)
    state.theme_items = selectors.filtered_themes(state.theme_filter, current, state.theme_allow_fallback)
    state.theme_cursor = 1
    preview_theme_choice(state, state.theme_items[state.theme_cursor])
    emit(ctx, "render")
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
  emit(ctx, "render")
end

function H.backspace(ctx)
  local state = ctx.state

  if state.mode == ui_state.modes.theme_select then
    state.theme_filter = state.theme_filter:sub(1, math.max(0, #state.theme_filter - 1))
    local current = state.selector_snapshot and state.selector_snapshot.colorscheme or (state.draft and state.draft.colorscheme)
    state.theme_items = selectors.filtered_themes(state.theme_filter, current, state.theme_allow_fallback)
    state.theme_cursor = 1
    preview_theme_choice(state, state.theme_items[state.theme_cursor])
    emit(ctx, "render")
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
    emit(ctx, "render")
  end
end

function H.request_delete(ctx)
  local state = ctx.state
  if state.mode ~= ui_state.modes.browse or state.section ~= ui_state.sections.schedule then
    return
  end

  local row = selected_row(state)
  if not row then
    state.message = "No schedule row selected."
    emit(ctx, "render")
    return
  end

  local entry = row.entry
  state.pending_delete = true
  state.message =
    string.format("Delete %s-%s %s? y delete / n or Esc cancel", entry.start, entry.stop, entry.colorscheme)
  emit(ctx, "render")
end

function H.confirm_delete(ctx)
  local state = ctx.state
  if not state.pending_delete then
    return
  end

  local row = selected_row(state)
  if row then
    table.remove(ctx.config.schedule, row.index)
    emit(ctx, "save_refresh")
  end
  clear_pending(state)
  clamp_cursor(state)
  emit(ctx, "render")
end

function H.toggle_hold(ctx)
  local state = ctx.state
  if ctx.status().pinned then
    emit(ctx, "unpin_session")
    state.message = "Session hold released."
    emit(ctx, "render")
    return
  end

  if state.draft then
    emit_pin_session(state.draft.colorscheme, state.draft.background, resolved_draft_background(state))
    emit(ctx, "preview_commit")
    set_mode_browse(state)
    state.message = "Held draft preview for this session."
    emit(ctx, "render")
    return
  end

  local status = ctx.status()
  emit_pin_session(status.colorscheme, status.requested_background, status.background)
  state.message = "Held current theme for this session."
  emit(ctx, "render")
end

function H.pin_browse(ctx)
  H.toggle_hold(ctx)
end

function H.pin_draft(ctx)
  H.toggle_hold(ctx)
end

function H.unpin(ctx)
  emit(ctx, "unpin_session")
  ctx.state.message = "Session hold released."
  emit(ctx, "render")
end

function H.toggle(ctx)
  if ctx.state.mode ~= ui_state.modes.browse then
    return
  end
  clear_pending(ctx.state)
  emit(ctx, "toggle_enabled")
  emit(ctx, "render")
end

function H.toggle_tui_colors(ctx)
  if ctx.state.mode ~= ui_state.modes.browse then
    return
  end
  clear_pending(ctx.state)
  emit(ctx, "toggle_tui_colors")
  ctx.state.message = "TUI colors switched to " .. (ctx.config.tui_colors == "theme" and "default" or "theme") .. " mode."
  emit(ctx, "render")
end

function H.reload(ctx)
  if ctx.state.mode ~= ui_state.modes.browse then
    return
  end
  clear_pending(ctx.state)
  emit(ctx, "core_reload")
  ctx.state.system_background = ctx.status().background
  ctx.state.message = "Reloaded configuration."
  emit(ctx, "render")
end

function H.help(ctx)
  emit(ctx, "notify_help", {
    text = table.concat({
      "colorful-times keys:",
      "  browse: Tab switches Defaults/Schedule, j/k move, Enter edit, a add, d delete, H hold/release, c colors, t toggle, q close",
      "  edit: Tab/j/k fields, type 0-9/: replaces active time, h/l cycles background on bg field, O session hold, S save, Esc cancel",
      "  theme selector: type filter, Backspace erase, j/k move, Enter choose, Esc cancel",
    }, "\n"),
  })
end

function H.left(ctx)
  local state = ctx.state
  if state.mode == ui_state.modes.edit then
    finish_time_input(state)
    if ui_state.active_field(state) == "background" then
      H.cycle_background(ctx, -1)
    end
    return
  end

  H.cycle_background(ctx, -1)
end

function H.right(ctx)
  local state = ctx.state
  if state.mode == ui_state.modes.edit then
    finish_time_input(state)
    if ui_state.active_field(state) == "background" then
      H.cycle_background(ctx, 1)
    end
    return
  end

  H.cycle_background(ctx, 1)
end

function H.close_or_cancel(ctx)
  if ctx.state.mode == ui_state.modes.browse and not ctx.state.pending_delete then
    if ctx.close then
      ctx.close()
    end
    return
  end
  H.cancel(ctx)
end

function M.dispatch(input, name, ...)
  local ctx = {
    state = input.state,
    config = input.config,
    status = input.status,
    preview_target = input.preview_target,
    close = input.close,
    current_background = input.current_background,
    effects = {},
  }
  local handler = H[name]
  if handler then
    CURRENT = ctx
    handler(ctx, ...)
    CURRENT = nil
  end
  return ctx.effects
end

return M
