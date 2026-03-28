-- lua/colorful-times/state.lua
local M = {}

local schedule = require("colorful-times.schedule")

---@param data table
---@return boolean ok
---@return string? error
function M.validate_state(data)
  if type(data) ~= "table" then
    return false, "state must be a table"
  end

  -- Validate enabled (if present)
  if data.enabled ~= nil and type(data.enabled) ~= "boolean" then
    return false, "enabled must be a boolean"
  end

  -- Validate schedule (if present)
  if data.schedule ~= nil then
    if type(data.schedule) ~= "table" then
      return false, "schedule must be an array"
    end
    -- Check it's an array (sequential integer keys)
    for k, _ in pairs(data.schedule) do
      if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
        return false, "schedule must be an array (sequential integer keys)"
      end
    end
    -- Validate each entry
    for idx, entry in ipairs(data.schedule) do
      local ok, err = schedule.validate_entry(entry)
      if not ok then
        return false, string.format("schedule entry %d: %s", idx, err)
      end
    end
  end

  -- Validate refresh_time (if present)
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

  -- Validate persist (if present)
  if data.persist ~= nil and type(data.persist) ~= "boolean" then
    return false, "persist must be a boolean"
  end

  -- Validate default (if present)
  if data.default ~= nil then
    if type(data.default) ~= "table" then
      return false, "default must be a table"
    end
    -- Validate default.background (if present)
    if data.default.background ~= nil then
      if not vim.tbl_contains({ "light", "dark", "system" }, data.default.background) then
        return false, "default.background must be one of: light, dark, system"
      end
    end
    -- Validate default.colorscheme (if present)
    if data.default.colorscheme ~= nil and type(data.default.colorscheme) ~= "string" then
      return false, "default.colorscheme must be a string"
    end
  end

  return true
end

---@return string
function M.path()
  return vim.fn.stdpath("data") .. "/colorful-times/state.json"
end

---@return table
function M.load()
  local path = M.path()
  local f = io.open(path, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then return {} end
  local ok, result = pcall(vim.json.decode, content)
  if not ok or type(result) ~= "table" then
    vim.notify(
      "colorful-times: failed to parse state file: " .. path,
      vim.log.levels.WARN
    )
    return {}
  end
  return result
end

---@param data table
function M.save(data)
  -- Validate data before writing
  local ok, err = M.validate_state(data)
  if not ok then
    vim.notify(
      "colorful-times: state validation failed: " .. (err or "unknown error"),
      vim.log.levels.ERROR
    )
    return
  end

  local path = M.path()
  local dir  = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  local f = io.open(path, "w")
  if not f then
    vim.notify(
      "colorful-times: could not write state file: " .. path,
      vim.log.levels.WARN
    )
    return
  end
  f:write(vim.json.encode(data))
  f:close()
end

---@param base_config table
---@param stored table
---@return table
function M.merge(base_config, stored)
  local result = vim.deepcopy(base_config)
  -- Only override keys that are explicitly present in stored
  if stored.schedule ~= nil then
    result.schedule = stored.schedule
  end
  if stored.enabled ~= nil then
    result.enabled = stored.enabled
  end
  if stored.refresh_time ~= nil then
    result.refresh_time = stored.refresh_time
  end
  if stored.persist ~= nil then
    result.persist = stored.persist
  end
  -- Deep merge for default table using vim.tbl_deep_extend
  -- Handle empty table case: empty stored.default should still overwrite
  if stored.default ~= nil then
    if next(stored.default) == nil then
      -- Empty table: direct assignment to overwrite base
      result.default = {}
    else
      result.default = vim.tbl_deep_extend("force", result.default or {}, stored.default)
    end
  end
  return result
end

return M
