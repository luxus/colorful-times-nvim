-- lua/colorful-times/system.lua
-- Streamlined system background detection

local M = {}
local uv = vim.uv

local _sysname

---@return string
function M.sysname()
  _sysname = _sysname or uv.os_uname().sysname
  return _sysname
end

---Check if system detection is available on this platform
---@return boolean
function M.has_detection()
  local cfg = require("colorful-times").config
  local sysname = M.sysname()
  return sysname == "Darwin" or sysname == "Linux" 
    or type(cfg.system_background_detection) == "function"
    or type(cfg.system_background_detection) == "table"
end

---Spawn process and capture exit code
---@param cmd string
---@param args string[]
---@param callback fun(code: integer)
local function spawn(cmd, args, callback)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  
  local handle
  handle = uv.spawn(cmd, { args = args, stdio = { nil, stdout, stderr } }, function(code)
    stdout:read_stop(); stderr:read_stop()
    stdout:close(); stderr:close()
    handle:close()
    callback(code)
  end)
  
  -- Drain pipes to prevent blocking
  stdout:read_start(function() end)
  stderr:read_start(function() end)
end

---@param cb fun(bg: "light" | "dark")
---@param fallback "light" | "dark"
function M.get_background(cb, fallback)
  local cfg = require("colorful-times").config
  local sysname = M.sysname()
  
  -- User-provided function
  if type(cfg.system_background_detection) == "function" then
    local bg = cfg.system_background_detection()
    vim.schedule(function() cb(bg == "dark" and "dark" or "light") end)
    return
  end
  
  -- User-provided command
  if type(cfg.system_background_detection) == "table" then
    spawn(cfg.system_background_detection[1], vim.list_slice(cfg.system_background_detection, 2), function(code)
      vim.schedule(function() cb(code == 0 and "dark" or "light") end)
    end)
    return
  end
  
  -- macOS detection
  if sysname == "Darwin" then
    spawn("defaults", { "read", "-g", "AppleInterfaceStyle" }, function(code)
      vim.schedule(function() cb(code == 0 and "dark" or "light") end)
    end)
    return
  end
  
  -- Linux detection
  if sysname == "Linux" then
    local script = cfg.system_background_detection_script
    if script then
      local stat = uv.fs_stat(script)
      if not stat or stat.type == "directory" or bit.band(stat.mode, tonumber("111", 8)) == 0 then
        vim.notify("colorful-times: invalid detection script: " .. script, vim.log.levels.ERROR)
        vim.schedule(function() cb(fallback) end)
        return
      end
      spawn(script, {}, function(code)
        vim.schedule(function() cb(code == 0 and "dark" or "light") end)
      end)
    else
      -- Auto-detect KDE/GNOME
      spawn("sh", { "-c", [[
        if [ "$XDG_CURRENT_DESKTOP" = "KDE" ] || [ "$XDG_SESSION_DESKTOP" = "KDE" ]; then
          if command -v kreadconfig6 &>/dev/null; then
            kreadconfig6 --group General --key ColorScheme --file kdeglobals | grep -q Dark && exit 0
          elif command -v kreadconfig5 &>/dev/null; then
            kreadconfig5 --group General --key ColorScheme --file kdeglobals | grep -q Dark && exit 0
          fi
          exit 1
        elif [ "$XDG_CURRENT_DESKTOP" = "GNOME" ] || [ "$XDG_SESSION_DESKTOP" = "GNOME" ]; then
          gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | grep -q prefer-dark && exit 0
          exit 1
        fi
        exit 1
      ]] }, function(code)
        vim.schedule(function() cb(code == 0 and "dark" or "light") end)
      end)
    end
    return
  end
  
  -- Unsupported platform
  vim.schedule(function() cb(fallback) end)
end

return M
