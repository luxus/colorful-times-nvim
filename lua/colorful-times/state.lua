-- lua/colorful-times/state.lua
-- Simplified state persistence

local M = {}
local uv = vim.uv

---@return string
function M.path()
  return vim.fn.stdpath("data") .. "/colorful-times/state.json"
end

-- Error code mapping
local ERROR_MESSAGES = {
  EACCES = "Permission denied",
  ENOENT = "File not found",
  ENOSPC = "Disk full",
  EROFS = "Read-only filesystem",
}

-- Static lookup for valid backgrounds
local VALID_BACKGROUNDS = { light = true, dark = true, system = true }

---Ensure the state directory exists without calling Vimscript in fast events.
---@param path string
---@return boolean ok
---@return string? error
local function ensure_parent_dir(path)
  local dir = vim.fs.dirname(path)
  if not dir or dir == "" then
    return true
  end

  local normalized = vim.fs.normalize(dir)
  local current = normalized:sub(1, 1) == "/" and "/" or ""

  for part in normalized:gmatch("[^/]+") do
    if current == "" or current == "/" then
      current = current == "/" and (current .. part) or part
    else
      current = current .. "/" .. part
    end

    local stat = uv.fs_stat(current)
    if not stat then
      local ok, err = uv.fs_mkdir(current, tonumber("755", 8))
      if not ok then
        return false, err
      end
    elseif stat.type ~= "directory" then
      return false, current .. " is not a directory"
    end
  end

  return true
end

---Validate state data structure with detailed errors
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
    -- Check it's an array (sequential integer keys)
    for k, _ in pairs(data.schedule) do
      if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
        return false, "schedule must be an array (sequential integer keys)"
      end
    end
    -- Validate each entry
    local schedule_mod = require("colorful-times.schedule")
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

  if data.default ~= nil then
    if type(data.default) ~= "table" then
      return false, "default must be a table"
    end
    if data.default.background ~= nil then
      if not VALID_BACKGROUNDS[data.default.background] then
        return false, "default.background must be one of: light, dark, system"
      end
    end
    if data.default.colorscheme ~= nil and type(data.default.colorscheme) ~= "string" then
      return false, "default.colorscheme must be a string"
    end
    if data.default.themes ~= nil then
      if type(data.default.themes) ~= "table" then
        return false, "default.themes must be a table"
      end
      for _, key in ipairs({ "light", "dark" }) do
        local theme = data.default.themes[key]
        if theme ~= nil and type(theme) ~= "string" then
          return false, "default.themes." .. key .. " must be a string"
        end
      end
    end
  end

  return true, nil
end

-- Alias for backwards compatibility
M.validate = M.validate_state

---Backup corrupted state file
---@param path string
---@return string backup_path
---@return boolean success
local function backup_corrupted(path)
  local timestamp = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  local backup_path = path .. ".bak." .. timestamp

  -- Try rename first (atomic)
  local ok = uv.fs_rename(path, backup_path)
  if ok then
    vim.notify("colorful-times: corrupted state backed up to " .. backup_path, vim.log.levels.WARN)
    return backup_path, true
  end

  -- Fallback: copy + delete
  local src_fd = uv.fs_open(path, uv.constants.O_RDONLY, 0)
  if not src_fd then
    vim.notify("colorful-times: failed to backup corrupted state", vim.log.levels.ERROR)
    return backup_path, false
  end

  local stat = uv.fs_fstat(src_fd)
  if not stat then
    uv.fs_close(src_fd)
    return backup_path, false
  end

  local content = uv.fs_read(src_fd, stat.size, 0)
  uv.fs_close(src_fd)

  if not content then
    return backup_path, false
  end

  local flags = bit.bor(uv.constants.O_WRONLY, uv.constants.O_CREAT, uv.constants.O_TRUNC)
  local dst_fd = uv.fs_open(backup_path, flags, tonumber("644", 8))
  if not dst_fd then
    return backup_path, false
  end

  uv.fs_write(dst_fd, content, 0)
  uv.fs_close(dst_fd)
  uv.fs_unlink(path)

  vim.notify("colorful-times: corrupted state backed up to " .. backup_path, vim.log.levels.WARN)
  return backup_path, true
end

---Load state from disk
---@return table data
function M.load()
  local path = M.path()
  local fd, err = uv.fs_open(path, uv.constants.O_RDONLY, 0)
  if not fd then
    if err and not err:match("ENOENT") then
      local code = err:match("^(%S+):")
      local msg = ERROR_MESSAGES[code] or ("Failed to open state file (" .. err .. ")")
      vim.notify("colorful-times: " .. msg .. ": " .. path, vim.log.levels.WARN)
    end
    return {}
  end

  local stat = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return {}
  end

  local content = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)

  if not content or content == "" then return {} end

  local ok, result = pcall(vim.json.decode, content)
  if not ok or type(result) ~= "table" then
    backup_corrupted(path)
    return {}
  end

  return result
end

---Save state to disk (atomic write via temp file + rename)
---@param data table
function M.save(data)
  local ok, err = M.validate_state(data)
  if not ok then
    vim.notify("colorful-times: state validation failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return
  end

  local path = M.path()
  local dir_ok, dir_err = ensure_parent_dir(path)
  if not dir_ok then
    vim.notify("colorful-times: could not create state directory: " .. (dir_err or path), vim.log.levels.ERROR)
    return
  end

  local content = vim.json.encode(data)
  local tmp_path = path .. ".tmp"
  local flags = bit.bor(uv.constants.O_WRONLY, uv.constants.O_CREAT, uv.constants.O_TRUNC)

  local fd, open_err = uv.fs_open(tmp_path, flags, tonumber("644", 8))
  if not fd then
    local code = open_err and open_err:match("^(%S+):")
    local msg = ERROR_MESSAGES[code] or ("Could not write state file (" .. (open_err or "unknown") .. ")")
    vim.notify("colorful-times: " .. msg .. ": " .. path, vim.log.levels.ERROR)
    return
  end

  local write_ok, write_err = pcall(function()
    return uv.fs_write(fd, content, 0)
  end)

  uv.fs_close(fd)

  if not write_ok or not write_err then
    vim.notify("colorful-times: failed to write state file: " .. path, vim.log.levels.ERROR)
    uv.fs_unlink(tmp_path)
    return
  end

  local rename_ok = uv.fs_rename(tmp_path, path)
  if not rename_ok then
    vim.notify("colorful-times: failed to rename temp state file: " .. path, vim.log.levels.ERROR)
    uv.fs_unlink(tmp_path)
  end
end

---Merge stored state into config
---@param config table
---@param stored table
---@return table
function M.merge(config, stored)
  local result = vim.deepcopy(config)

  for _, key in ipairs({ "enabled", "schedule", "refresh_time", "persist" }) do
    if stored[key] ~= nil then result[key] = stored[key] end
  end

  if stored.default ~= nil and type(stored.default) == "table" then
    result.default = vim.tbl_deep_extend("force", result.default or {}, stored.default)
  end

  return result
end

return M
