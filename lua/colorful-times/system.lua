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

-- Static set of supported platforms
local SUPPORTED_SYSNAMES = { Darwin = true, Linux = true }

---Check if system detection is available on this platform
---@return boolean
function M.has_detection()
  local cfg = require("colorful-times").config
  local sysname = M.sysname()
  return SUPPORTED_SYSNAMES[sysname]
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

local _last_bg
local _last_check_time = 0
local _pending_cb = nil
local _debounce_timer = nil

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
  
  -- macOS detection with debouncing to handle stale defaults cache
  if sysname == "Darwin" then
    local now = uv.now()
    
    -- If we checked very recently (within 100ms), return cached result
    if now - _last_check_time < 100 and _last_bg then
      vim.schedule(function() cb(_last_bg) end)
      return
    end
    
    -- Cancel any pending debounce
    if _debounce_timer and not _debounce_timer:is_closing() then
      _debounce_timer:stop()
      _debounce_timer:close()
    end
    
    _pending_cb = cb
    _last_check_time = now
    
    spawn("defaults", { "read", "-g", "AppleInterfaceStyle" }, function(code)
      local detected = code == 0 and "dark" or "light"
      
      -- If result changed from last known value, verify after a short delay
      -- to handle macOS defaults cache inconsistency
      if _last_bg and detected ~= _last_bg then
        _debounce_timer = uv.new_timer()
        _debounce_timer:start(100, 0, function()
          _debounce_timer:close()
          spawn("defaults", { "read", "-g", "AppleInterfaceStyle" }, function(code2)
            local verified = code2 == 0 and "dark" or "light"
            _last_bg = verified
            vim.schedule(function()
              if _pending_cb then
                _pending_cb(verified)
                _pending_cb = nil
              end
            end)
          end)
        end)
      else
        _last_bg = detected
        vim.schedule(function()
          if _pending_cb then
            _pending_cb(detected)
            _pending_cb = nil
          end
        end)
      end
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
