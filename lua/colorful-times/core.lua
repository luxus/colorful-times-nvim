-- lua/colorful-times/core.lua
local M        = require("colorful-times")
local schedule = require("colorful-times.schedule")
local system   = require("colorful-times.system")
local state    = require("colorful-times.state")
local uv       = vim.uv

-- Module-level mutable state
local _timer      -- uv_timer_t|nil  (schedule boundary timer)
local _poll_timer -- uv_timer_t|nil  (appearance poll timer)
local _previous_bg  -- string|nil
local _focused = true

local function stop_timer(t)
  if t and not t:is_closing() then
    t:stop()
    t:close()
  end
end

-- Return current time as minutes since midnight
local function now_mins()
  local d = os.date("*t")
  return d.hour * 60 + d.min
end

-- Determine the colorscheme + background to apply right now.
-- Returns: colorscheme string, background string
local function resolve_theme()
  local cfg    = M.config
  local parsed = schedule.preprocess(cfg.schedule, cfg.default.background)
  local active = M.config.enabled and schedule.get_active_entry(parsed, now_mins())

  local bg, cs
  if active then
    bg = active.background
    cs = active.colorscheme
  else
    bg = cfg.default.background
    -- theme-specific default colorscheme
    if bg ~= "system" and cfg.default.themes and cfg.default.themes[bg] then
      cs = cfg.default.themes[bg]
    else
      cs = cfg.default.colorscheme
    end
  end
  return cs, bg
end

-- Set colorscheme + background synchronously (must be called from main thread / vim.schedule)
local function set_colorscheme(cs, bg)
  _previous_bg    = bg
  vim.o.background = bg
  local ok, err = pcall(vim.cmd.colorscheme, cs)
  if not ok then
    vim.notify("colorful-times: failed to apply colorscheme '" .. cs .. "': " .. err,
      vim.log.levels.ERROR)
  end
end

-- Two-phase apply: sync fallback first, then async system check if needed.
---@return nil
function M.apply_colorscheme()
  local cs, bg = resolve_theme()

  if bg ~= "system" then
    -- Non-system: apply directly
    vim.schedule(function() set_colorscheme(cs, bg) end)
    return
  end

  -- System background: apply fallback immediately, then correct asynchronously
  local fallback = _previous_bg or vim.o.background or "dark"
  local fallback_cs = cs
  if M.config.default.themes and M.config.default.themes[fallback] then
    fallback_cs = M.config.default.themes[fallback]
  end

  -- Phase 1: sync fallback
  vim.schedule(function() set_colorscheme(fallback_cs, fallback) end)

  -- Phase 2: async real value
  system.get_background(function(detected_bg)
    if detected_bg ~= _previous_bg then
      local real_cs = cs
      if M.config.default.themes and M.config.default.themes[detected_bg] then
        real_cs = M.config.default.themes[detected_bg]
      end
      vim.schedule(function() set_colorscheme(real_cs, detected_bg) end)
    end
  end, fallback)
end

-- Schedule the one-shot _timer to fire at the next schedule boundary
local function arm_schedule_timer()
  stop_timer(_timer)
  _timer = nil
  if not M.config.enabled then return end

  local parsed   = schedule.preprocess(M.config.schedule, M.config.default.background)
  local diff_min = schedule.next_change_at(parsed, now_mins())
  if not diff_min then return end

  _timer = uv.new_timer()
  _timer:start(diff_min * 60 * 1000, 0, function()
    vim.schedule(function()
      M.apply_colorscheme()
      arm_schedule_timer()
    end)
  end)
end

-- Check on each poll tick whether we actually need to query the OS
local function needs_system_poll()
  local parsed = schedule.preprocess(M.config.schedule, M.config.default.background)
  local active = M.config.enabled and schedule.get_active_entry(parsed, now_mins())
  local bg     = active and active.background or M.config.default.background
  return bg == "system"
end

-- Start the repeating appearance poll _timer
local function start_poll_timer()
  stop_timer(_poll_timer)
  _poll_timer = nil

  local sysname = system.sysname()
  if sysname ~= "Darwin" and sysname ~= "Linux"
    and type(M.config.system_background_detection) ~= "function"
    and type(M.config.system_background_detection) ~= "table"
  then
    return  -- no system detection available
  end

  local fallback = _previous_bg or vim.o.background or "dark"
  _poll_timer = uv.new_timer()
  _poll_timer:start(0, M.config.refresh_time, function()
    if not _focused then return end
    if not needs_system_poll() then return end
    system.get_background(function(detected_bg)
      if detected_bg ~= _previous_bg then
        M.apply_colorscheme()
      end
    end, fallback)
  end)
end

local autocmd_registered = false

local function register_focus_autocmds()
  if autocmd_registered then return end
  autocmd_registered = true
  local grp = vim.api.nvim_create_augroup("ColorfulTimesFocus", { clear = true })
  vim.api.nvim_create_autocmd("FocusLost", {
    group = grp,
    callback = function() _focused = false end,
  })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = grp,
    callback = function()
      _focused = true
      -- Re-check appearance immediately on focus regain
      if needs_system_poll() then
        local fallback = _previous_bg or vim.o.background or "dark"
        system.get_background(function(detected_bg)
          if detected_bg ~= _previous_bg then
            M.apply_colorscheme()
          end
        end, fallback)
      end
    end,
  })
end

local function enable_plugin()
  M.apply_colorscheme()
  arm_schedule_timer()
  start_poll_timer()
  vim.notify("colorful-times: enabled", vim.log.levels.INFO)
end

local function disable_plugin()
  stop_timer(_timer);      _timer = nil
  stop_timer(_poll_timer); _poll_timer = nil
  -- Apply with enabled=false so resolve_theme() returns default
  M.apply_colorscheme()
  vim.notify("colorful-times: disabled", vim.log.levels.INFO)
end

-- Validation helpers for setup()
---@param opts table
---@return boolean ok
---@return string? error
local function validate_opts(opts)
  -- Validate opts.enabled
  if opts.enabled ~= nil and type(opts.enabled) ~= "boolean" then
    return false, "opts.enabled must be a boolean"
  end

  -- Validate opts.refresh_time
  if opts.refresh_time ~= nil then
    if type(opts.refresh_time) ~= "number" or opts.refresh_time < 1000 then
      return false, "opts.refresh_time must be an integer >= 1000"
    end
  end

  -- Validate opts.persist
  if opts.persist ~= nil and type(opts.persist) ~= "boolean" then
    return false, "opts.persist must be a boolean"
  end

  -- Validate opts.schedule
  if opts.schedule ~= nil then
    if type(opts.schedule) ~= "table" or (#opts.schedule == 0 and next(opts.schedule)) then
      return false, "opts.schedule must be an array"
    end
    for idx, entry in ipairs(opts.schedule) do
      local ok, err = schedule.validate_entry(entry)
      if not ok then
        return false, string.format("opts.schedule[%d]: %s", idx, err)
      end
    end
  end

  -- Validate opts.default.background
  if opts.default and opts.default.background ~= nil then
    local valid_bgs = { light = true, dark = true, system = true }
    if not valid_bgs[opts.default.background] then
      return false, "opts.default.background must be 'light', 'dark', or 'system'"
    end
  end

  -- Validate opts.system_background_detection
  if opts.system_background_detection ~= nil then
    local t = type(opts.system_background_detection)
    if t ~= "function" then
      if t ~= "table" then
        return false, "opts.system_background_detection must be a function or array of strings"
      end
      -- Check it's a non-empty array of strings
      if #opts.system_background_detection == 0 then
        return false, "opts.system_background_detection array must not be empty"
      end
      for i, v in ipairs(opts.system_background_detection) do
        if type(v) ~= "string" or v == "" then
          return false, string.format("opts.system_background_detection[%d] must be a non-empty string", i)
        end
      end
    end
  end

  return true
end

---@return nil
function M.toggle()
  M.config.enabled = not M.config.enabled
  if M.config.enabled then enable_plugin() else disable_plugin() end
end

---@return nil
function M.reload()
  stop_timer(_timer);      _timer = nil
  stop_timer(_poll_timer); _poll_timer = nil
  _previous_bg = nil
  schedule.preprocess(M.config.schedule, M.config.default.background)  -- re-validate
  M.apply_colorscheme()
  arm_schedule_timer()
  start_poll_timer()
end

---@param opts ColorfulTimes.Config?
---@return nil
function M.setup(opts)
  -- Validate before any state changes
  if opts then
    local ok, err = validate_opts(opts)
    if not ok then
      vim.notify("colorful-times: " .. err, vim.log.levels.ERROR)
      return
    end
  end

  -- Merge user opts into config
  if opts then
    local safe_opts = vim.deepcopy(opts)
    if safe_opts.default then
      M.config.default = vim.tbl_deep_extend("force", M.config.default, safe_opts.default)
      safe_opts.default = nil
    end
    for k, v in pairs(safe_opts) do
      M.config[k] = v
    end
  end

  -- Merge persisted state on top
  local stored = state.load()
  if type(stored) == "table" and next(stored) then
    M.config = state.merge(M.config, stored)
  end

  register_focus_autocmds()

  if M.config.enabled then
    M.apply_colorscheme()
    arm_schedule_timer()
    start_poll_timer()
  end
end

-- TUI entry point
---@return nil
function M.open()
  require("colorful-times.tui").open()
end

return M
