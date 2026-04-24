-- lua/colorful-times/tui/selectors.lua
-- Theme and background selector helpers.

local M = {}

local MAX_COLORSCHEMES = 300
local _cached_schemes

local BG_CHOICES = { "system", "light", "dark" }
local FALLBACK_LABEL = "(fallback)"

---@return string[]
function M.colorschemes()
  if _cached_schemes then
    return _cached_schemes
  end

  local seen = {}
  _cached_schemes = {}
  for _, name in ipairs(vim.fn.getcompletion("", "color")) do
    if name ~= "" and not seen[name] then
      seen[name] = true
      _cached_schemes[#_cached_schemes + 1] = name
      if #_cached_schemes >= MAX_COLORSCHEMES then
        break
      end
    end
  end

  return _cached_schemes
end

function M.clear_cache()
  _cached_schemes = nil
end

---@param filter string
---@param current? string
---@param allow_fallback? boolean
---@return string[]
function M.filtered_themes(filter, current, allow_fallback)
  local needle = vim.trim(filter or ""):lower()
  local items = {}
  local seen = {}

  if allow_fallback then
    items[#items + 1] = FALLBACK_LABEL
    seen[FALLBACK_LABEL] = true
  end

  local function add(name)
    if not name or name == "" or seen[name] then
      return
    end
    if needle ~= "" and not name:lower():find(needle, 1, true) then
      return
    end
    seen[name] = true
    items[#items + 1] = name
  end

  add(current)
  for _, name in ipairs(M.colorschemes()) do
    add(name)
  end

  return items
end

---@param items string[]
---@param current? string
---@return integer
function M.index_of(items, current)
  if not current or current == "" then
    return 1
  end
  for idx, item in ipairs(items) do
    if item == current then
      return idx
    end
  end
  return 1
end

---@param bg? string
---@return integer
function M.background_index(bg)
  for idx, item in ipairs(BG_CHOICES) do
    if item == bg then
      return idx
    end
  end
  return 1
end

---@param bg? string
---@param delta integer
---@return string
function M.cycle_background(bg, delta)
  local idx = M.background_index(bg)
  idx = ((idx - 1 + delta) % #BG_CHOICES) + 1
  return BG_CHOICES[idx]
end

---@param bg? string
---@return string
function M.resolved_background(bg)
  if bg == "system" then
    local current = vim.o.background
    if current == "light" or current == "dark" then
      return current
    end
    return "dark"
  end
  if bg == "light" or bg == "dark" then
    return bg
  end
  return "dark"
end

---@return string[]
function M.background_choices()
  return vim.deepcopy(BG_CHOICES)
end

function M.fallback_label()
  return FALLBACK_LABEL
end

return M
