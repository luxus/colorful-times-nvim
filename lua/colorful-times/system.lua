-- lua/colorful-times/system.lua
-- System background detection with single-flight Darwin detector

local M = {}
local uv = vim.uv

local _sysname

local VALID_BACKGROUNDS = { light = true, dark = true }

---@return string
function M.sysname()
  _sysname = _sysname or uv.os_uname().sysname
  return _sysname
end

---@param path unknown
---@return boolean
local function is_executable_file(path)
  if type(path) ~= "string" or path == "" then
    return false
  end

  local stat = uv.fs_stat(path)
  if not stat or stat.type == "directory" then
    return false
  end

  return bit.band(stat.mode, tonumber("111", 8)) ~= 0
end

---@param value unknown
---@return boolean
local function is_non_empty_string(value)
  return type(value) == "string" and value ~= ""
end

---@param value unknown
---@return string?
---@return string[]?
---@return string?
local function parse_command_override(value)
  if type(value) ~= "table" then
    return nil, nil, nil
  end

  local cmd = value[1]
  if not is_non_empty_string(cmd) then
    return nil, nil, "custom detection command must start with a non-empty executable name"
  end

  local args = {}
  for idx = 2, #value do
    if type(value[idx]) ~= "string" then
      return nil, nil, "custom detection command arguments must be strings"
    end
    args[#args + 1] = value[idx]
  end

  return cmd, args, nil
end

---@return string
local function current_desktop()
  return (vim.env.XDG_CURRENT_DESKTOP or vim.env.XDG_SESSION_DESKTOP or ""):upper()
end

---@return boolean
local function is_kde()
  return current_desktop():find("KDE", 1, true) ~= nil
end

---@return boolean
local function is_gnome()
  return current_desktop():find("GNOME", 1, true) ~= nil
end

---@class ColorfulTimes.DetectionInfo
---@field available boolean
---@field backend string
---@field detail string

---Describe the currently available system detection backend.
---@return ColorfulTimes.DetectionInfo
function M.detection_info()
  local cfg = require("colorful-times").config
  local sysname = M.sysname()

  if type(cfg.system_background_detection) == "function" then
    return {
      available = true,
      backend = "function",
      detail = "custom Lua function override",
    }
  end

  if type(cfg.system_background_detection) == "table" then
    local cmd = parse_command_override(cfg.system_background_detection)
    if cmd then
      return {
        available = true,
        backend = "command",
        detail = "custom command override",
      }
    end
    return {
      available = false,
      backend = "command",
      detail = "custom command override is invalid",
    }
  end

  if sysname == "Darwin" then
    return {
      available = true,
      backend = "darwin",
      detail = "macOS appearance detection (osascript with defaults fallback)",
    }
  end

  if sysname == "Linux" then
    if cfg.system_background_detection_script ~= nil then
      if is_executable_file(cfg.system_background_detection_script) then
        return {
          available = true,
          backend = "script",
          detail = "custom detection script",
        }
      end
      return {
        available = false,
        backend = "script",
        detail = "custom detection script is missing or not executable",
      }
    end

    if is_kde() then
      if vim.fn.executable("kreadconfig6") == 1 or vim.fn.executable("kreadconfig5") == 1 then
        return {
          available = true,
          backend = "linux-kde",
          detail = "KDE desktop detection",
        }
      end
      return {
        available = false,
        backend = "linux-kde",
        detail = "KDE detected but kreadconfig5/6 is unavailable",
      }
    end

    if is_gnome() then
      if vim.fn.executable("gsettings") == 1 then
        return {
          available = true,
          backend = "linux-gnome",
          detail = "GNOME desktop detection",
        }
      end
      return {
        available = false,
        backend = "linux-gnome",
        detail = "GNOME detected but gsettings is unavailable",
      }
    end

    return {
      available = false,
      backend = "linux",
      detail = "no supported Linux desktop detected (expected KDE or GNOME)",
    }
  end

  return {
    available = false,
    backend = "unsupported",
    detail = "platform is unsupported for automatic detection",
  }
end

---Check if system detection is available on this platform
---@return boolean
function M.has_detection()
  return M.detection_info().available
end

-- ─── Process Helpers ─────────────────────────────────────────────────────────

---Spawn process, capture stdout/stderr, and return results via callback
---@param cmd string
---@param args string[]
---@param callback fun(code: integer|nil, stdout: string, stderr: string)
local function spawn_capture(cmd, args, callback)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local out, err = {}, {}

  local handle
  handle = uv.spawn(cmd, { args = args, stdio = { nil, stdout, stderr } }, function(code)
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()
    if handle and not handle:is_closing() then
      handle:close()
    end
    callback(code, table.concat(out), table.concat(err))
  end)

  if not handle then
    stdout:close()
    stderr:close()
    callback(nil, "", "spawn failed: " .. cmd)
    return
  end

  stdout:read_start(function(_, data)
    if data then out[#out + 1] = data end
  end)
  stderr:read_start(function(_, data)
    if data then err[#err + 1] = data end
  end)
end

---Spawn process and return only exit code (legacy compat for Linux paths)
---@param cmd string
---@param args string[]
---@param callback fun(code: integer|nil)
local function spawn(cmd, args, callback)
  spawn_capture(cmd, args, function(code)
    callback(code)
  end)
end

-- ─── Darwin Single-Flight Detector ──────────────────────────────────────────

local _last_bg
local _darwin_inflight = false
local _darwin_waiters = {}

---Resolve all pending Darwin waiters with the detected background
---@param bg string|nil
---@param fallback string|nil
local function _finish_darwin(bg, fallback)
  local resolved = bg or _last_bg or fallback or "dark"
  _last_bg = resolved

  local waiters = _darwin_waiters
  _darwin_waiters = {}
  _darwin_inflight = false

  vim.schedule(function()
    for _, waiter in ipairs(waiters) do
      waiter(resolved)
    end
  end)
end

---Query macOS appearance: osascript primary, defaults fallback
---@param cb fun(bg: "light"|"dark")
local function _query_macos(cb)
  spawn_capture("osascript", {
    "-e",
    'tell application "System Events" to tell appearance preferences to get dark mode',
  }, function(code, out)
    if code == 0 then
      local value = out:gsub("%s+", "")
      if value == "true" then return cb("dark") end
      if value == "false" then return cb("light") end
    end

    -- Fallback: defaults read (less reliable for automation-triggered changes)
    spawn_capture("defaults", { "read", "-g", "AppleInterfaceStyle" }, function(code2)
      cb(code2 == 0 and "dark" or "light")
    end)
  end)
end

---Single-flight Darwin detection with bounded retry on first-seen change
---@param cb fun(bg: "light"|"dark")
---@param fallback string
local function _detect_darwin(cb, fallback)
  table.insert(_darwin_waiters, cb)
  if _darwin_inflight then return end
  _darwin_inflight = true

  _query_macos(function(first)
    -- If unchanged from last known, accept immediately
    if _last_bg ~= nil and first == _last_bg then
      _finish_darwin(first, fallback)
      return
    end

    -- New value detected — bounded retry to confirm (handles plist lag)
    local retries = { 250, 500 }
    local i = 1

    local function retry_or_finish(current)
      local delay = retries[i]
      if not delay then
        _finish_darwin(current, fallback)
        return
      end
      i = i + 1

      local timer = uv.new_timer()
      timer:start(delay, 0, function()
        if not timer:is_closing() then
          timer:stop()
          timer:close()
        end
        _query_macos(function(next_bg)
          if next_bg == current then
            _finish_darwin(next_bg, fallback)
          else
            retry_or_finish(next_bg)
          end
        end)
      end)
    end

    retry_or_finish(first)
  end)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

---Detect system background asynchronously
---@param cb fun(bg: "light"|"dark")
---@param fallback "light"|"dark"
function M.get_background(cb, fallback)
  local cfg = require("colorful-times").config
  local sysname = M.sysname()

  -- User-provided function (synchronous)
  if type(cfg.system_background_detection) == "function" then
    local ok, bg = pcall(cfg.system_background_detection)
    if ok and VALID_BACKGROUNDS[bg] then
      vim.schedule(function() cb(bg) end)
      return
    end

    local message = ok and "custom detection function must return 'light' or 'dark'"
      or ("custom detection function failed: " .. tostring(bg))
    vim.notify("colorful-times: " .. message, vim.log.levels.WARN)
    vim.schedule(function() cb(fallback) end)
    return
  end

  -- User-provided command
  if type(cfg.system_background_detection) == "table" then
    local cmd, args, err = parse_command_override(cfg.system_background_detection)
    if not cmd then
      vim.notify("colorful-times: " .. (err or "invalid custom detection command"), vim.log.levels.WARN)
      vim.schedule(function() cb(fallback) end)
      return
    end

    spawn(cmd, args, function(code)
      vim.schedule(function()
        if code == nil then
          vim.notify("colorful-times: custom detection command failed to start", vim.log.levels.WARN)
          cb(fallback)
          return
        end
        cb(code == 0 and "dark" or "light")
      end)
    end)
    return
  end

  -- macOS: single-flight osascript → defaults fallback
  if sysname == "Darwin" then
    _detect_darwin(cb, fallback)
    return
  end

  -- Linux detection
  if sysname == "Linux" then
    local script = cfg.system_background_detection_script
    if script then
      if not is_executable_file(script) then
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
