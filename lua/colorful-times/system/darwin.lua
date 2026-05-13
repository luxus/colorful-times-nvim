-- lua/colorful-times/system/darwin.lua

local M = {}

local _last_bg
local _inflight = false
local _waiters = {}

function M.plan()
  return {
    available = true,
    backend = "darwin",
    detail = "macOS appearance detection (osascript with defaults fallback)",
    kind = "darwin_appearance",
  }
end

local function finish(bg, fallback)
  local resolved = bg or _last_bg or fallback or "dark"
  _last_bg = resolved

  local waiters = _waiters
  _waiters = {}
  _inflight = false

  vim.schedule(function()
    for _, waiter in ipairs(waiters) do
      waiter(resolved)
    end
  end)
end

local function query(process, cb)
  process.spawn_capture("osascript", {
    "-e",
    'tell application "System Events" to tell appearance preferences to get dark mode',
  }, function(code, out)
    if code == 0 then
      local value = out:gsub("%s+", "")
      if value == "true" then return cb("dark") end
      if value == "false" then return cb("light") end
    end

    process.spawn_capture("defaults", { "read", "-g", "AppleInterfaceStyle" }, function(code2)
      cb(code2 == 0 and "dark" or "light")
    end)
  end)
end

function M.run(process, cb, fallback)
  table.insert(_waiters, cb)
  if _inflight then return end
  _inflight = true

  query(process, function(first)
    if _last_bg ~= nil and first == _last_bg then
      finish(first, fallback)
      return
    end

    local retries = { 250, 500 }
    local i = 1

    local function retry_or_finish(current)
      local delay = retries[i]
      if not delay then
        finish(current, fallback)
        return
      end
      i = i + 1

      local timer = vim.uv.new_timer()
      timer:start(delay, 0, function()
        if not timer:is_closing() then
          timer:stop()
          timer:close()
        end
        query(process, function(next_bg)
          if next_bg == current then
            finish(next_bg, fallback)
          else
            retry_or_finish(next_bg)
          end
        end)
      end)
    end

    retry_or_finish(first)
  end)
end

return M
