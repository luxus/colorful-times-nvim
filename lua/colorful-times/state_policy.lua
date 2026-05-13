-- lua/colorful-times/state_policy.lua
-- Persisted state shape, merge, and JSON codec policy.

local M = {}

local VALID_BACKGROUNDS = { light = true, dark = true, system = true }
local THEME_KEYS = { "light", "dark" }
local VALID_TUI_COLORS = { default = true, theme = true }
local STATE_KEYS = { "enabled", "schedule", "refresh_time", "persist", "tui_colors" }

---@param data table
---@return boolean ok
---@return string? error
function M.validate_state(data)
  if type(data) ~= "table" then
    return false, "state must be a table"
  end

  if data.enabled ~= nil and type(data.enabled) ~= "boolean" then
    return false, "enabled must be a boolean"
  end

  if data.persist ~= nil and type(data.persist) ~= "boolean" then
    return false, "persist must be a boolean"
  end

  if data.schedule ~= nil then
    if type(data.schedule) ~= "table" then
      return false, "schedule must be an array"
    end
    for k, _ in pairs(data.schedule) do
      if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
        return false, "schedule must be an array (sequential integer keys)"
      end
    end
    local schedule_mod = require("colorful-times.schedule_runtime")
    for idx, entry in ipairs(data.schedule) do
      local ok, err = schedule_mod.validate_entry(entry)
      if not ok then
        return false, string.format("schedule entry %d: %s", idx, err)
      end
    end
  end

  if data.refresh_time ~= nil then
    if type(data.refresh_time) ~= "number" then
      return false, "refresh_time must be a number"
    end
    if data.refresh_time <= 0 then
      return false, "refresh_time must be a positive integer"
    end
    if data.refresh_time ~= math.floor(data.refresh_time) then
      return false, "refresh_time must be an integer"
    end
  end

  if data.tui_colors ~= nil then
    if type(data.tui_colors) ~= "string" or not VALID_TUI_COLORS[data.tui_colors] then
      return false, "tui_colors must be 'default' or 'theme'"
    end
  end

  if data.default ~= nil then
    if type(data.default) ~= "table" then
      return false, "default must be a table"
    end
    if data.default.background ~= nil and not VALID_BACKGROUNDS[data.default.background] then
      return false, "default.background must be one of: light, dark, system"
    end
    if data.default.colorscheme ~= nil and type(data.default.colorscheme) ~= "string" then
      return false, "default.colorscheme must be a string"
    end
    if data.default.themes ~= nil then
      if type(data.default.themes) ~= "table" then
        return false, "default.themes must be a table"
      end
      for _, key in ipairs(THEME_KEYS) do
        local theme = data.default.themes[key]
        if theme ~= nil and type(theme) ~= "string" then
          return false, "default.themes." .. key .. " must be a string"
        end
      end
    end
  end

  return true, nil
end

M.validate = M.validate_state

---@param bytes string
---@return table? data
---@return string? error
function M.decode(bytes)
  if type(bytes) ~= "string" or bytes == "" then
    return {}, nil
  end

  local ok, result = pcall(vim.json.decode, bytes)
  if not ok or type(result) ~= "table" then
    return nil, "state JSON must decode to a table"
  end

  local valid, err = M.validate_state(result)
  if not valid then
    return nil, err
  end

  return result, nil
end

---@param data table
---@return string? bytes
---@return string? error
function M.encode(data)
  local ok, err = M.validate_state(data)
  if not ok then
    return nil, err
  end

  local encode_ok, encoded = pcall(vim.json.encode, data)
  if not encode_ok then
    return nil, tostring(encoded)
  end
  return encoded, nil
end

---@param config table
---@param stored table
---@return table
function M.merge(config, stored)
  local result = vim.deepcopy(config)

  for _, key in ipairs(STATE_KEYS) do
    if stored[key] ~= nil then result[key] = stored[key] end
  end

  if stored.default ~= nil and type(stored.default) == "table" then
    result.default = vim.tbl_deep_extend("force", result.default or {}, stored.default)
  end

  return result
end

return M
