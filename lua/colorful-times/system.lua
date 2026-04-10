-- lua/colorful-times/system.lua
-- System background detection with single-flight Darwin detector

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

  -- macOS: single-flight osascript → defaults fallback
  if sysname == "Darwin" then
    _detect_darwin(cb, fallback)
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
