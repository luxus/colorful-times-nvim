-- lua/colorful-times/tui/layout.lua
-- Window sizing helpers for the one-root-float TUI.

local M = {}

local MIN_WIDTH = 70
local MIN_HEIGHT = 16

---@return table
function M.current_ui()
  local ui = vim.api.nvim_list_uis()[1] or {}
  local width = ui.width
  local height = ui.height
  if not width or width <= 0 then
    width = vim.o.columns
  end
  if not height or height <= 0 then
    height = vim.o.lines
  end
  return {
    width = math.max(1, width or MIN_WIDTH),
    height = math.max(1, height or MIN_HEIGHT),
  }
end

---@param lines string[]
---@return integer
local function widest_line(lines)
  local width = MIN_WIDTH
  for _, line in ipairs(lines or {}) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  return width
end

---@param lines string[]
---@return table
function M.window_config(lines)
  local ui = M.current_ui()
  local max_width = math.max(1, ui.width - 4)
  local max_height = math.max(1, ui.height - 4)
  local width = math.min(math.max(1, widest_line(lines) + 2), max_width)
  local height = math.min(math.max(1, #lines), max_height)

  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((ui.height - height) / 2),
    col = math.floor((ui.width - width) / 2),
    style = "minimal",
    border = "rounded",
  }
end

return M
