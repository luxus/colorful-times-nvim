-- lua/colorful-times/system/env.lua
-- Env/executable adapter for system background detection.

local M = {}
local uv = vim.uv

function M.sysname()
  return uv.os_uname().sysname
end

function M.current_desktop()
  return (vim.env.XDG_CURRENT_DESKTOP or vim.env.XDG_SESSION_DESKTOP or ""):upper()
end

function M.executable(name)
  return vim.fn.executable(name) == 1
end

function M.is_executable_file(path)
  if type(path) ~= "string" or path == "" then
    return false
  end

  local stat = uv.fs_stat(path)
  if not stat or stat.type == "directory" then
    return false
  end

  return bit.band(stat.mode, tonumber("111", 8)) ~= 0
end

return M
