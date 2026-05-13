-- lua/colorful-times/state.lua
-- Persisted state filesystem adapter.

local M = {}
local uv = vim.uv
local policy = require("colorful-times.state_policy")

---@return string
function M.path()
  return vim.fn.stdpath("data") .. "/colorful-times/state.json"
end

local ERROR_MESSAGES = {
  EACCES = "Permission denied",
  ENOENT = "File not found",
  ENOSPC = "Disk full",
  EROFS = "Read-only filesystem",
}

local function fs_error_message(err, fallback)
  local code = err and err:match("^(%S+):")
  return ERROR_MESSAGES[code] or (fallback .. " (" .. (err or "unknown") .. ")")
end

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

---@param path string
---@return string backup_path
---@return boolean success
local function backup_corrupted(path)
  local timestamp = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  local backup_path = path .. ".bak." .. timestamp

  local ok = uv.fs_rename(path, backup_path)
  if ok then
    vim.notify("colorful-times: corrupted state backed up to " .. backup_path, vim.log.levels.WARN)
    return backup_path, true
  end

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

  local flags = bit.bor(uv.constants.O_WRONLY, uv.constants.O_CREAT, uv.constants.O_EXCL)
  local dst_fd = uv.fs_open(backup_path, flags, tonumber("600", 8))
  if not dst_fd then
    return backup_path, false
  end

  uv.fs_write(dst_fd, content, 0)
  uv.fs_close(dst_fd)
  uv.fs_unlink(path)

  vim.notify("colorful-times: corrupted state backed up to " .. backup_path, vim.log.levels.WARN)
  return backup_path, true
end

---@return string? bytes
---@return string? error
local function read_bytes(path)
  local fd, err = uv.fs_open(path, uv.constants.O_RDONLY, 0)
  if not fd then
    return nil, err
  end

  local stat = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return nil, "could not stat state file"
  end

  local content = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  return content, nil
end

---@param path string
---@param bytes string
---@return boolean ok
---@return string? error
local function write_atomic(path, bytes)
  local dir_ok, dir_err = ensure_parent_dir(path)
  if not dir_ok then
    return false, "could not create state directory: " .. (dir_err or path)
  end

  local tmp_path = path .. ".tmp"
  uv.fs_unlink(tmp_path)

  local flags = bit.bor(uv.constants.O_WRONLY, uv.constants.O_CREAT, uv.constants.O_EXCL)
  local fd, open_err = uv.fs_open(tmp_path, flags, tonumber("600", 8))
  if not fd then
    return false, fs_error_message(open_err, "Could not write state file")
  end

  local write_ok, wrote = pcall(function()
    return uv.fs_write(fd, bytes, 0)
  end)
  uv.fs_close(fd)

  if not write_ok or not wrote then
    uv.fs_unlink(tmp_path)
    return false, "failed to write state file"
  end

  local rename_ok = uv.fs_rename(tmp_path, path)
  if not rename_ok then
    uv.fs_unlink(tmp_path)
    return false, "failed to rename temp state file"
  end

  return true, nil
end

M.validate_state = policy.validate_state
M.validate = policy.validate
M.merge = policy.merge

---@return table data
function M.load()
  local path = M.path()
  local bytes, err = read_bytes(path)
  if not bytes then
    if err and not err:match("ENOENT") then
      vim.notify("colorful-times: " .. fs_error_message(err, "Failed to open state file") .. ": " .. path, vim.log.levels.WARN)
    end
    return {}
  end

  local data, _ = policy.decode(bytes)
  if not data then
    backup_corrupted(path)
    return {}
  end

  return data
end

---@param data table
function M.save(data)
  local bytes, encode_err = policy.encode(data)
  if not bytes then
    vim.notify("colorful-times: state validation failed: " .. (encode_err or "unknown"), vim.log.levels.ERROR)
    return
  end

  local path = M.path()
  local ok, err = write_atomic(path, bytes)
  if not ok then
    vim.notify("colorful-times: " .. (err or "failed to write state file") .. ": " .. path, vim.log.levels.ERROR)
  end
end

return M
