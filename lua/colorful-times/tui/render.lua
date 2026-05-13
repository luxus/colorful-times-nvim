-- lua/colorful-times/tui/render.lua
-- Neovim adapter for Colorful Times TUI render plans.

local M = {}
local api = vim.api
local ct = require("colorful-times")
local core = require("colorful-times.core")
local layout = require("colorful-times.tui.layout")
local highlights = require("colorful-times.tui.highlights")
local render_plan = require("colorful-times.tui.render_plan")

local function each_char(text)
  return tostring(text or ""):gmatch("()([%z\1-\127\194-\244][\128-\191]*)")
end

local function display_col_to_byte_col(line, target_col)
  target_col = math.max(0, target_col or 0)
  local display_col = 0
  for byte_start, char in each_char(line) do
    local char_width = vim.fn.strdisplaywidth(char)
    if display_col + char_width > target_col then
      return byte_start - 1
    end
    display_col = display_col + char_width
  end
  return #tostring(line or "")
end

local function current_minute()
  local now = os.date("*t")
  return now.hour * 60 + now.min
end

local function build_plan(state)
  return render_plan.build({
    config = ct.config,
    status = core.status(),
    state = state,
    now_minute = current_minute(),
    current_colorscheme = vim.g.colors_name,
    current_background = vim.o.background,
    ui = layout.current_ui(),
    width_fn = vim.fn.strdisplaywidth,
  })
end

---@param app table
function M.draw(app)
  if not (app.buf and api.nvim_buf_is_valid(app.buf)) then
    return
  end

  local plan = build_plan(app.state)
  local lines, marks, status = plan.lines, plan.marks, plan.status
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
    local line = lines[mark.line] or ""
    local start_col = display_col_to_byte_col(line, mark.start or 0)
    local stop_col = mark.stop or -1
    if stop_col >= 0 then
      stop_col = display_col_to_byte_col(line, stop_col)
    end
    api.nvim_buf_add_highlight(app.buf, ns, mark.group, mark.line - 1, start_col, stop_col)
    if mark.group == "ColorfulTimesField" or mark.group == "ColorfulTimesSelected" then
      cursor_line = mark.line
      cursor_col = display_col_to_byte_col(line, mark.cursor_col or 0)
    end
  end

  if app.win and api.nvim_win_is_valid(app.win) and cursor_line then
    pcall(api.nvim_win_set_cursor, app.win, { cursor_line, cursor_col })
  end

  if status.pinned then
    api.nvim_buf_set_extmark(app.buf, ns, 0, 0, {
      virt_text = { { "SESSION HOLD", "ColorfulTimesPinned" } },
      virt_text_pos = "right_align",
    })
  end
end

return M
