-- lua/colorful-times/state.lua
local M = {}

local schedule = require("colorful-times.schedule")
local uv = vim.uv
local bit = require("bit")

-- Platform detection for file locking support
local _is_windows = uv.os_uname().sysname:match("Windows") ~= nil
local _flock_available = not _is_windows

-- Flock constants (from sys/file.h)
local LOCK_SH = 1   -- Shared lock (for reading)
local LOCK_EX = 2   -- Exclusive lock (for writing)
local LOCK_NB = 4   -- Non-blocking (fail immediately if locked)
local LOCK_UN = 8   -- Unlock

---Acquire a file lock using vim.uv.fs_flock()
---@param fd number File descriptor
---@param exclusive boolean Whether to use exclusive lock (write) or shared (read)
---@param timeout_ms number? Optional timeout in ms for retry (default: 5000)
---@return boolean ok True if lock acquired
---@return string? error Error message if failed
local function acquire_lock(fd, exclusive, timeout_ms)
  if not _flock_available then
    return true -- Silently skip on Windows
  end

  timeout_ms = timeout_ms or 5000
  local lock_type = exclusive and LOCK_EX or LOCK_SH
  local start_time = uv.hrtime() / 1e6 -- Convert to ms
  local retry_delay = 10 -- Initial retry delay in ms

  while true do
    local ok, err = uv.fs_flock(fd, lock_type)
    if ok then
      return true
    end

    -- Check if we should retry (only retry if file is locked, not for other errors)
    local elapsed = (uv.hrtime() / 1e6) - start_time
    if elapsed >= timeout_ms then
      return false, "Timeout waiting for file lock"
    end

    -- Exponential backoff with cap
    vim.wait(math.min(retry_delay, 100))
    retry_delay = math.min(retry_delay * 2, 100)
  end
end

---Release a file lock
---@param fd number File descriptor
---@return boolean ok
local function release_lock(fd)
  if not _flock_available then
    return true
  end

  local ok, _ = uv.fs_flock(fd, LOCK_UN)
  return ok or false
end

-- Error code to human-readable message mapping
local ERROR_MESSAGES = {
  EACCES = "Permission denied",
  ENOENT = "Directory does not exist",
  ENOSPC = "Disk full",
  EROFS = "Read-only filesystem",
  EISDIR = "Path is a directory",
  EINVAL = "Invalid argument",
  EIO = "I/O error",
  ENFILE = "Too many open files",
  EMFILE = "Too many open files",
}

---@param err string|nil
---@return boolean
local function is_enoent(err)
  return err and err:match("^ENOENT") ~= nil
end

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

---@param path string
---@return string backup_path
---@return boolean success
local function backup_corrupted_file(path)
  -- Use higher precision timestamp (microseconds via uv.hrtime if available, or os.time + counter)
  local timestamp = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  local backup_path = path .. ".bak." .. timestamp

  -- Try rename first (atomic)
  local ok, err = uv.fs_rename(path, backup_path)
  if ok then
    vim.notify(
      "colorful-times: corrupted state backed up to " .. backup_path,
      vim.log.levels.WARN
    )
    return backup_path, true
  end

  -- Fallback: copy + delete
  local src_fd, src_err = uv.fs_open(path, uv.constants.O_RDONLY, 0)
  if not src_fd then
    vim.notify(
      "colorful-times: failed to backup corrupted state (open error: " .. (src_err or "unknown") .. ")",
      vim.log.levels.ERROR
    )
    return backup_path, false
  end

  local stat = uv.fs_fstat(src_fd)
  if not stat then
    uv.fs_close(src_fd)
    vim.notify(
      "colorful-times: failed to backup corrupted state (stat error)",
      vim.log.levels.ERROR
    )
    return backup_path, false
  end

  local content = uv.fs_read(src_fd, stat.size, 0)
  uv.fs_close(src_fd)

  if not content then
    vim.notify(
      "colorful-times: failed to backup corrupted state (read error)",
      vim.log.levels.ERROR
    )
    return backup_path, false
  end

  local flags = bit.bor(uv.constants.O_WRONLY, uv.constants.O_CREAT, uv.constants.O_TRUNC)
  local mode = tonumber("644", 8)

  local dst_fd, dst_err = uv.fs_open(backup_path, flags, mode)
  if not dst_fd then
    vim.notify(
      "colorful-times: failed to backup corrupted state (create error: " .. (dst_err or "unknown") .. ")",
      vim.log.levels.ERROR
    )
    return backup_path, false
  end

  local written = uv.fs_write(dst_fd, content, 0)
  uv.fs_close(dst_fd)

  if not written then
    vim.notify(
      "colorful-times: failed to backup corrupted state (write error)",
      vim.log.levels.ERROR
    )
    return backup_path, false
  end

  -- Delete original after successful copy
  uv.fs_unlink(path)

  vim.notify(
    "colorful-times: corrupted state backed up to " .. backup_path,
    vim.log.levels.WARN
  )
  return backup_path, true
end

---@return string
function M.path()
  return vim.fn.stdpath("data") .. "/colorful-times/state.json"
end

---@return table
function M.load()
  local path = M.path()

  -- Use vim.uv.fs_open for better error reporting
  local fd, err = uv.fs_open(path, uv.constants.O_RDONLY, 0)
  if not fd then
    if not is_enoent(err) then
      local code = err and err:match("^(%S+):") or err
      local msg = ERROR_MESSAGES[code] or ("Failed to open state file (" .. (err or "unknown") .. ")")
      vim.notify(
        "colorful-times: " .. msg .. ": " .. path,
        vim.log.levels.WARN
      )
    end
    return {}
  end

  -- Acquire shared lock for reading
  local lock_ok, lock_err = acquire_lock(fd, false, 5000)
  if not lock_ok then
    uv.fs_close(fd)
    vim.notify(
      "colorful-times: " .. (lock_err or "Failed to acquire file lock") .. ": " .. path,
      vim.log.levels.WARN
    )
    return {}
  end

  local stat = uv.fs_fstat(fd)
  if not stat then
    release_lock(fd)
    uv.fs_close(fd)
    return {}
  end

  local content = uv.fs_read(fd, stat.size, 0)
  release_lock(fd)
  uv.fs_close(fd)

  if not content or content == "" then return {} end

  local ok, result = pcall(vim.json.decode, content)
  if not ok or type(result) ~= "table" then
    -- Backup corrupted file before returning empty state
    backup_corrupted_file(path)
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

  local content = vim.json.encode(data)
  local flags = bit.bor(uv.constants.O_WRONLY, uv.constants.O_CREAT, uv.constants.O_TRUNC)
  local mode = tonumber("644", 8)

  -- Use vim.uv.fs_open for better error reporting
  local fd, err = uv.fs_open(path, flags, mode)
  if not fd then
    local code = err and err:match("^(%S+):") or err
    local msg = ERROR_MESSAGES[code] or ("Could not write state file (" .. (err or "unknown") .. ")")
    vim.notify(
      "colorful-times: " .. msg .. ": " .. path,
      vim.log.levels.ERROR
    )
    return
  end

  -- Acquire exclusive lock before writing
  local lock_ok, lock_err = acquire_lock(fd, true, 5000)
  if not lock_ok then
    uv.fs_close(fd)
    vim.notify(
      "colorful-times: " .. (lock_err or "Failed to acquire file lock") .. ": " .. path,
      vim.log.levels.ERROR
    )
    return
  end

  -- Ensure lock is released even on error using pcall
  local success, write_err = pcall(function()
    return uv.fs_write(fd, content, 0)
  end)

  release_lock(fd)
  uv.fs_close(fd)

  if not success or not write_err then
    vim.notify(
      "colorful-times: failed to write state file: " .. path .. " (" .. tostring(write_err or "unknown") .. ")",
      vim.log.levels.ERROR
    )
  end
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
