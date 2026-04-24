-- lua/colorful-times/tui/layout.lua
-- Window sizing helpers for the one-root-float TUI.

local M = {}

local MIN_WIDTH = 70
local MIN_HEIGHT = 16

---@return table
function M.current_ui()
  local ui = vim.api.nvim_list_uis()[1] or {}
  return {
    width = math.max(ui.width or 0, vim.o.columns, MIN_WIDTH + 4),
    height = math.max(ui.height or 0, vim.o.lines - 2, MIN_HEIGHT + 4),
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
  local width = math.min(math.max(MIN_WIDTH, widest_line(lines) + 2), math.max(MIN_WIDTH, ui.width - 4))
  local height = math.min(math.max(MIN_HEIGHT, #lines), math.max(MIN_HEIGHT, ui.height - 4))

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
