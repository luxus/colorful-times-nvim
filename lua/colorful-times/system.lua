-- lua/colorful-times/system.lua
local M = {}
local uv = vim.uv
local bit = require("bit")

local _sysname = nil

---@return string
function M.sysname()
  if not _sysname then
    _sysname = uv.os_uname().sysname or "Unknown"
  end
  return _sysname
end

-- Spawn a process and call handle_result(exit_code) when done.
-- Drains stdout/stderr to prevent pipe blocking.
---@param cmd string
---@param args string[]
---@param handle_result fun(code: integer)
local function spawn_check(cmd, args, handle_result)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local handle
  handle = uv.spawn(cmd, { args = args, stdio = { nil, stdout, stderr } },
    function(code)
      stdout:read_stop(); stderr:read_stop()
      stdout:close();     stderr:close()
      handle:close()
      handle_result(code)
    end)
  stdout:read_start(function() end)
  stderr:read_start(function() end)
end

---@param cb fun(bg: string)
---@param fallback string
function M.get_background(cb, fallback)
  local config = require("colorful-times").config
  local sysname = M.sysname()

  -- User-supplied function (Linux)
  if type(config.system_background_detection) == "function" then
    local bg = config.system_background_detection()
    vim.schedule(function() cb(bg) end)
    return
  end

  -- User-supplied command table (Linux)
  if type(config.system_background_detection) == "table" then
    local cmd  = config.system_background_detection[1]
    local args = vim.list_slice(config.system_background_detection, 2)
    spawn_check(cmd, args, function(code)
      vim.schedule(function() cb(code == 0 and "dark" or "light") end)
    end)
    return
  end

  if sysname == "Darwin" then
    spawn_check("defaults", { "read", "-g", "AppleInterfaceStyle" }, function(code)
      vim.schedule(function() cb(code == 0 and "dark" or "light") end)
    end)

  elseif sysname == "Linux" then
    local config = require("colorful-times").config
    local script = config.system_background_detection_script

    if script then
      -- Validate script exists and is executable
      local stat = uv.fs_stat(script)
      if not stat then
        vim.notify("colorful-times: script not found: " .. script, vim.log.levels.ERROR)
        vim.schedule(function() cb(fallback) end)
        return
      end
      if stat.type == "directory" then
        vim.notify("colorful-times: script path is a directory: " .. script, vim.log.levels.ERROR)
        vim.schedule(function() cb(fallback) end)
        return
      end
      if bit.band(stat.mode, tonumber("111", 8)) == 0 then
        vim.notify("colorful-times: script not executable: " .. script, vim.log.levels.ERROR)
        vim.schedule(function() cb(fallback) end)
        return
      end
      -- Execute custom script: exit 0 = dark, exit 1 = light
      spawn_check(script, {}, function(code)
        vim.schedule(function() cb(code == 0 and "dark" or "light") end)
      end)
    else
      -- Auto-detect KDE or GNOME using default inline script
      local default_script = [[
        if [ "$XDG_CURRENT_DESKTOP" = "KDE" ] || [ "$XDG_SESSION_DESKTOP" = "KDE" ]; then
          if command -v kreadconfig6 &>/dev/null; then
            kreadconfig6 --group General --key ColorScheme --file kdeglobals | grep -q Dark && exit 0
            kreadconfig6 --group KDE --key LookAndFeelPackage | grep -qi dark && exit 0
          elif command -v kreadconfig5 &>/dev/null; then
            kreadconfig5 --group General --key ColorScheme --file kdeglobals | grep -q Dark && exit 0
          fi
          exit 1
        elif [ "$XDG_CURRENT_DESKTOP" = "GNOME" ] || [ "$XDG_SESSION_DESKTOP" = "GNOME" ]; then
          gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | grep -q prefer-dark && exit 0
          exit 1
        else
          exit 1
        fi
      ]]
      spawn_check("sh", { "-c", default_script }, function(code)
        vim.schedule(function() cb(code == 0 and "dark" or "light") end)
      end)
    end

  else
    vim.schedule(function() cb(fallback) end)
  end
end

return M
