-- lua/colorful-times/tui/preview.lua
-- Reversible live preview service for the TUI.

local M = {}

local snapshot = nil

local function concrete_background(background, resolved_background)
  if background == "system" then
    if resolved_background == "light" or resolved_background == "dark" then
      return resolved_background
    end
    local current = vim.o.background
    if current == "light" or current == "dark" then
      return current
    end
    return "dark"
  end
  if background == "light" or background == "dark" then
    return background
  end
  return vim.o.background or "dark"
end

local function apply_raw(colorscheme, background)
  if background and background ~= "" then
    vim.o.background = background
  end
  if colorscheme and colorscheme ~= "" then
    pcall(vim.cmd.colorscheme, colorscheme)
  end
end

local function apply_on_main(fn)
  if vim.in_fast_event() then
    vim.schedule(fn)
  else
    fn()
  end
end

function M.begin()
  if snapshot then
    return
  end

  snapshot = {
    colorscheme = vim.g.colors_name,
    background = vim.o.background,
  }
end

---@param colorscheme? string
---@param background? string
---@param resolved_background? string
function M.apply(colorscheme, background, resolved_background)
  local bg = concrete_background(background, resolved_background)
  apply_on_main(function()
    apply_raw(colorscheme, bg)
  end)
end

function M.commit()
  snapshot = nil
end

function M.restore()
  if not snapshot then
    return
  end

  local original = snapshot
  snapshot = nil
  apply_on_main(function()
    apply_raw(original.colorscheme, original.background)
  end)
end

---@return boolean
function M.active()
  return snapshot ~= nil
end

---@return table|nil
function M.snapshot()
  return snapshot and vim.deepcopy(snapshot) or nil
end

return M
