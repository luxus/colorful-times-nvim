-- lua/colorful-times/tui/render.lua
-- Renders the one-buffer Colorful Times TUI.

local M = {}
local api = vim.api
local ct = require("colorful-times")
local core = require("colorful-times.core")
local layout = require("colorful-times.tui.layout")
local view_model = require("colorful-times.tui.view_model")
local ui_state = require("colorful-times.tui.state")
local highlights = require("colorful-times.tui.highlights")

local VERSION = "2.3.0"
local TIMELINE_WIDTH = 78
local MAX_SELECTOR_ROWS = 8
local MIN_THEME_WIDTH = 32
local MAX_THEME_WIDTH = 46
local PANEL_WIDTH = 108

local function add(lines, text)
  lines[#lines + 1] = text
  return #lines
end

local function sep()
  return "  " .. string.rep("─", PANEL_WIDTH)
end

local function fit(text, width)
  text = tostring(text or "")
  local display_width = vim.fn.strdisplaywidth(text)
  if display_width > width then
    return text:sub(1, math.max(1, width - 1))
  end
  return text .. string.rep(" ", width - display_width)
end

local function frame_title(title, focused)
  local label = focused and ("● " .. title) or ("○ " .. title)
  local prefix = "─ " .. label .. " "
  return "  " .. prefix .. string.rep("─", math.max(1, PANEL_WIDTH - vim.fn.strdisplaywidth(prefix)))
end

local function frame_end()
  return sep()
end

local function frame_row(text)
  return "    " .. fit(text, PANEL_WIDTH - 2)
end

local function centered(text)
  local width = PANEL_WIDTH
  local display_width = vim.fn.strdisplaywidth(text)
  local left = math.max(0, math.floor((width - display_width) / 2))
  return "  " .. string.rep(" ", left) .. text
end

local function centered_full(text)
  local display_width = vim.fn.strdisplaywidth(text)
  local left = math.max(0, math.floor((PANEL_WIDTH - display_width) / 2))
  return "  " .. fit(string.rep(" ", left) .. text, PANEL_WIDTH)
end

local function timeline(rows, now, now_label)
  local chars = {}
  for i = 1, TIMELINE_WIDTH do
    chars[i] = "·"
  end

  local function mark_range(start_time, stop_time)
    local start_col = math.floor(start_time / 1440 * TIMELINE_WIDTH) + 1
    local stop_col = math.floor(stop_time / 1440 * TIMELINE_WIDTH) + 1
    start_col = math.max(1, math.min(TIMELINE_WIDTH, start_col))
    stop_col = math.max(1, math.min(TIMELINE_WIDTH + 1, stop_col))
    for col = start_col, math.max(start_col, stop_col - 1) do
      chars[col] = "━"
    end
  end

  for _, row in ipairs(rows) do
    local start_time = row.start_time
    local stop_time = require("colorful-times.schedule").parse_time(row.entry.stop) or start_time
    if stop_time <= start_time then
      mark_range(start_time, 1440)
      mark_range(0, stop_time)
    else
      mark_range(start_time, stop_time)
    end
  end

  local now_col = math.floor(now / 1440 * TIMELINE_WIDTH) + 1
  now_col = math.max(1, math.min(TIMELINE_WIDTH, now_col))
  chars[now_col] = "┃"

  return "  00:00 " .. table.concat(chars) .. " 24:00  now " .. now_label
end

local function bg_segment(value)
  local items = {}
  for _, bg in ipairs({ "system", "light", "dark" }) do
    if value == bg then
      items[#items + 1] = "[ " .. bg .. " ]"
    else
      items[#items + 1] = "  " .. bg .. "  "
    end
  end
  return table.concat(items, " ")
end

local function source_label(status)
  if status.pinned then
    return "session hold"
  end
  return status.source or "default"
end

local function header(lines, marks, vm)
  local status = vm.status
  local enabled = vm.enabled and "Enabled" or "Disabled"
  local title = "Colorful Times v" .. VERSION
  add(lines, centered(title))
  add(
    lines,
    string.format(
      "  Schedule: %s | Active Colorscheme: %s | Background: %s",
      enabled,
      status.colorscheme or "?",
      status.background or "?"
    )
  )
  add(lines, "  Source  " .. source_label(status) .. "  · requested bg " .. (status.requested_background or "?"))
  local timeline_lnum = add(lines, timeline(vm.rows, vm.now, vm.now_label))
  marks[#marks + 1] = { line = 1, group = "ColorfulTimesTitle", start = 0, stop = -1 }
  marks[#marks + 1] = { line = timeline_lnum, group = "ColorfulTimesTimeline", start = 8, stop = 8 + TIMELINE_WIDTH }
  add(lines, sep())
end

local function defaults(lines, marks, vm)
  local default = vm.default or {}
  local focused = vm.ui.section == ui_state.sections.defaults
  local frame_group = focused and "ColorfulTimesFrameFocus" or "ColorfulTimesFrame"
  local title_lnum = add(lines, frame_title("DEFAULTS", focused))
  marks[#marks + 1] = { line = title_lnum, group = frame_group, start = 2, stop = -1 }

  local rows = {
    {
      label = "Fallback theme",
      value = view_model.display_theme(default.colorscheme),
      hint = "used when no schedule/theme override matches",
      col = 22,
    },
    {
      label = "Fallback bg",
      value = view_model.display_cell(default.background),
      hint = "system follows detected OS light/dark",
      col = 22,
    },
    {
      label = "Light override",
      value = view_model.display_theme(default.themes and default.themes.light),
      hint = "optional theme when resolved bg is light",
      col = 22,
    },
    {
      label = "Dark override",
      value = view_model.display_theme(default.themes and default.themes.dark),
      hint = "optional theme when resolved bg is dark",
      col = 22,
    },
  }

  for idx, row in ipairs(rows) do
    local marker = focused and vm.ui.default_cursor == idx and "▸" or " "
    local line = frame_row(string.format("%s %-15s %-18s  %s", marker, row.label, row.value, row.hint))
    local lnum = add(lines, line)

    marks[#marks + 1] = { line = lnum, group = "ColorfulTimesDim", start = 43, stop = -1 }
    if focused and vm.ui.default_cursor == idx then
      marks[#marks + 1] = { line = lnum, group = "ColorfulTimesSelected", cursor_col = row.col }
    end
  end
  local end_lnum = add(lines, frame_end())
  marks[#marks + 1] = { line = end_lnum, group = frame_group, start = 2, stop = -1 }
end

local function theme_width(vm)
  local width = MIN_THEME_WIDTH
  local function consider(value)
    width = math.max(width, vim.fn.strdisplaywidth(view_model.display_theme(value)) + 1)
  end

  consider(vm.default and vm.default.colorscheme)
  consider(vm.default and vm.default.themes and vm.default.themes.light)
  consider(vm.default and vm.default.themes and vm.default.themes.dark)
  if vm.ui.draft then
    consider(vm.ui.draft.colorscheme)
  end
  for _, row in ipairs(vm.rows) do
    consider(row.entry.colorscheme)
  end

  return math.min(MAX_THEME_WIDTH, width)
end

local function schedule_table(lines, marks, vm, cols)
  local focused = vm.ui.section == ui_state.sections.schedule
  local frame_group = focused and "ColorfulTimesFrameFocus" or "ColorfulTimesFrame"
  local title_lnum = add(lines, frame_title("SCHEDULE", focused))
  marks[#marks + 1] = { line = title_lnum, group = frame_group, start = 2, stop = -1 }
  local header_lnum = add(
    lines,
    frame_row(
      view_model.pad("", 3)
        .. view_model.pad("START", 8)
        .. view_model.pad("STOP", 8)
        .. view_model.pad("COLORSCHEME", cols.theme)
        .. view_model.pad("BG", 10)
        .. "STATE"
    )
  )

  if #vm.rows == 0 then
    add(lines, frame_row("(no entries — press a to add)"))
    local empty_end_lnum = add(lines, frame_end())
    marks[#marks + 1] = { line = empty_end_lnum, group = frame_group, start = 2, stop = -1 }
    return
  end

  for display_index, row in ipairs(vm.rows) do
    local entry = row.entry
    local prefix = focused and display_index == vm.ui.cursor and "▸ " or "  "
    local state = row.active and "● active" or ""
    local line = frame_row(
      view_model.pad(prefix, 3)
        .. view_model.pad(entry.start, 8)
        .. view_model.pad(entry.stop, 8)
        .. view_model.pad(view_model.display_theme(entry.colorscheme), cols.theme)
        .. view_model.pad(view_model.display_cell(entry.background), 10)
        .. state
    )
    local lnum = add(lines, line)
    if focused and display_index == vm.ui.cursor then
      marks[#marks + 1] =
        { line = lnum, group = "ColorfulTimesSelected", start = 4, stop = PANEL_WIDTH, cursor_col = 7 }
    elseif row.active then
      marks[#marks + 1] = { line = lnum, group = "ColorfulTimesActive", start = 0, stop = -1 }
    end
  end
  local end_lnum = add(lines, frame_end())
  marks[#marks + 1] = { line = end_lnum, group = frame_group, start = 2, stop = -1 }
end

local function edit_drawer(lines, marks, state)
  local draft = state.draft
  if not draft then
    return
  end

  if
    state.draft_kind == "default_colorscheme"
    or state.draft_kind == "default_background"
    or state.draft_kind == "default_light"
    or state.draft_kind == "default_dark"
  then
    local title = "Edit Default"
    if state.draft_kind == "default_light" then
      title = "Edit Light Override"
    elseif state.draft_kind == "default_dark" then
      title = "Edit Dark Override"
    end

    local title_lnum = add(lines, frame_title(title:upper(), true))
    marks[#marks + 1] = { line = title_lnum, group = "ColorfulTimesFrameFocus", start = 2, stop = -1 }
    if state.draft_kind == "default_background" then
      add(lines, frame_row("› BACKGROUND  " .. bg_segment(draft.background)))
    else
      add(lines, frame_row("› THEME       " .. view_model.display_theme(draft.colorscheme)))
    end
    add(lines, frame_row(""))
    add(lines, frame_row("Preview now"))
    add(
      lines,
      frame_row(
        "  " .. view_model.display_theme(draft.colorscheme) .. " • bg " .. view_model.display_cell(draft.background)
      )
    )
    local end_lnum = add(lines, frame_end())
    marks[#marks + 1] = { line = end_lnum, group = "ColorfulTimesFrameFocus", start = 2, stop = -1 }
    return
  end

  local title = state.draft_kind == "add" and "Add Entry" or "Edit Entry"
  local title_lnum = add(lines, frame_title(title:upper(), true))
  marks[#marks + 1] = { line = title_lnum, group = "ColorfulTimesFrameFocus", start = 2, stop = -1 }
  local dirty = state.draft_kind == "add"
  if state.draft_kind == "edit" and state.edit_index and ct.config.schedule[state.edit_index] then
    local original = ct.config.schedule[state.edit_index]
    dirty = draft.start ~= original.start
      or draft.stop ~= original.stop
      or draft.colorscheme ~= original.colorscheme
      or draft.background ~= original.background
  end

  local field = ui_state.active_field(state)
  local fields = {
    { key = "start", label = "START", value = draft.start, col = 17 },
    { key = "stop", label = "STOP", value = draft.stop, col = 17 },
    { key = "colorscheme", label = "THEME", value = view_model.display_theme(draft.colorscheme), col = 17 },
    { key = "background", label = "BACKGROUND", value = bg_segment(draft.background), col = 17 },
  }

  for _, item in ipairs(fields) do
    local marker = item.key == field and "›" or " "
    local line = frame_row(string.format("%s %-11s %s", marker, item.label, view_model.display_cell(item.value)))
    local lnum = add(lines, line)
    if item.key == field then
      local cursor_col = item.col + 1
      if (item.key == "start" or item.key == "stop") and state.time_input_field == item.key then
        cursor_col = item.col + vim.fn.strdisplaywidth(tostring(item.value or "")) + 1
      end
      marks[#marks + 1] = {
        line = lnum,
        group = "ColorfulTimesField",
        start = 4,
        stop = PANEL_WIDTH,
        cursor_col = cursor_col,
      }
    end
  end

  add(lines, frame_row(""))
  add(lines, frame_row("Preview now"))
  add(
    lines,
    frame_row(
      "  " .. view_model.display_theme(draft.colorscheme) .. " • bg " .. view_model.display_cell(draft.background)
    )
  )
  local end_lnum = add(lines, frame_end())
  marks[#marks + 1] = { line = end_lnum, group = "ColorfulTimesFrameFocus", start = 2, stop = -1 }
  state._dirty = dirty
end

local function selector_window(lines, marks, state)
  if state.mode == ui_state.modes.theme_select then
    local filter = state.theme_filter ~= "" and state.theme_filter or "∅"
    local title_lnum = add(lines, frame_title("THEME  type to filter  [" .. filter .. "]", true))
    marks[#marks + 1] = { line = title_lnum, group = "ColorfulTimesFrameFocus", start = 2, stop = -1 }
    if #state.theme_items == 0 then
      add(lines, frame_row("(no matching colorschemes)"))
      local end_lnum = add(lines, frame_end())
      marks[#marks + 1] = { line = end_lnum, group = "ColorfulTimesFrameFocus", start = 2, stop = -1 }
      return
    end

    local start = math.max(1, state.theme_cursor - math.floor(MAX_SELECTOR_ROWS / 2))
    local stop = math.min(#state.theme_items, start + MAX_SELECTOR_ROWS - 1)
    start = math.max(1, math.min(start, math.max(1, stop - MAX_SELECTOR_ROWS + 1)))

    for idx = start, stop do
      local prefix = idx == state.theme_cursor and "▸ " or "  "
      local lnum = add(lines, frame_row(prefix .. state.theme_items[idx]))
      if idx == state.theme_cursor then
        marks[#marks + 1] =
          { line = lnum, group = "ColorfulTimesSelected", start = 4, stop = PANEL_WIDTH, cursor_col = 7 }
      end
    end
    local end_lnum = add(lines, frame_end())
    marks[#marks + 1] = { line = end_lnum, group = "ColorfulTimesFrameFocus", start = 2, stop = -1 }
  elseif state.mode == ui_state.modes.bg_select then
    local title_lnum = add(lines, frame_title("BACKGROUND", true))
    marks[#marks + 1] = { line = title_lnum, group = "ColorfulTimesFrameFocus", start = 2, stop = -1 }
    local bg_lnum = add(lines, frame_row(bg_segment(state.draft and state.draft.background or "system")))
    marks[#marks + 1] =
      { line = bg_lnum, group = "ColorfulTimesSelected", start = 4, stop = PANEL_WIDTH, cursor_col = 7 }
    local end_lnum = add(lines, frame_end())
    marks[#marks + 1] = { line = end_lnum, group = "ColorfulTimesFrameFocus", start = 2, stop = -1 }
  end
end

local function footer(lines, marks, state)
  if state.message then
    add(lines, "")
    if state.pending_delete then
      local lnum = add(lines, centered_full("⚠  " .. state.message .. "  ⚠"))
      lines[#lines + 1] = ""
      return lnum
    else
      add(lines, "  " .. state.message)
    end
  end

  if state.mode == ui_state.modes.browse then
    add(lines, "  Tab switch panel  j/k move  <CR> edit  a add schedule  d delete schedule")
    add(lines, "  H hold/release session theme  t toggle  r reload  q quit")
  elseif state.mode == ui_state.modes.edit then
    add(lines, "  Tab/j/k field  0-9/: replace time  <CR> select  h/l cycles background")
    local lnum = add(lines, "  S save  O session hold  Esc cancel")
    if state._dirty then
      marks[#marks + 1] = { line = lnum, group = "ColorfulTimesWarn", start = 2, stop = 8 }
    end
  elseif state.mode == ui_state.modes.theme_select then
    add(lines, "  type filter  BS erase  j/k move  <CR> choose  Esc cancel")
  elseif state.mode == ui_state.modes.bg_select then
    add(lines, "  h/l or j/k cycle  <CR> choose  Esc cancel")
  end
end

local function render_lines(state)
  local status = core.status()
  local vm = view_model.build(ct.config, status, state)
  local cols = { theme = theme_width(vm) }
  local lines, marks = {}, {}

  header(lines, marks, vm)
  defaults(lines, marks, vm)
  schedule_table(lines, marks, vm, cols)
  edit_drawer(lines, marks, state)
  selector_window(lines, marks, state)
  local danger_line = footer(lines, marks, state)
  if danger_line then
    marks[#marks + 1] = { line = danger_line, group = "ColorfulTimesDanger", start = 0, stop = -1 }
  end

  return lines, marks, status
end

---@param app table
function M.draw(app)
  if not (app.buf and api.nvim_buf_is_valid(app.buf)) then
    return
  end

  local lines, marks, status = render_lines(app.state)
  local ns = highlights.ns()

  vim.bo[app.buf].modifiable = true
  api.nvim_buf_clear_namespace(app.buf, ns, 0, -1)
  api.nvim_buf_set_lines(app.buf, 0, -1, false, lines)
  vim.bo[app.buf].modifiable = false

  if app.win and api.nvim_win_is_valid(app.win) then
    api.nvim_win_set_config(app.win, layout.window_config(lines))
  end

  local cursor_line = nil
  local cursor_col = 0
  for _, mark in ipairs(marks) do
    api.nvim_buf_add_highlight(app.buf, ns, mark.group, mark.line - 1, mark.start or 0, mark.stop or -1)
    if mark.group == "ColorfulTimesField" or mark.group == "ColorfulTimesSelected" then
      cursor_line = mark.line
      cursor_col = mark.cursor_col or 0
    end
  end

  if app.win and api.nvim_win_is_valid(app.win) and cursor_line then
    pcall(api.nvim_win_set_cursor, app.win, { cursor_line, cursor_col })
  end

  api.nvim_buf_add_highlight(app.buf, ns, "ColorfulTimesTitle", 0, 0, -1)
  api.nvim_buf_add_highlight(app.buf, ns, "ColorfulTimesAccent", 1, 0, -1)
  api.nvim_buf_add_highlight(app.buf, ns, "ColorfulTimesMuted", 2, 0, -1)

  if status.pinned then
    api.nvim_buf_set_extmark(app.buf, ns, 0, 0, {
      virt_text = { { "SESSION HOLD", "ColorfulTimesPinned" } },
      virt_text_pos = "right_align",
    })
  end
end

return M
