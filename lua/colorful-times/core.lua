-- lua/colorful-times/core.lua
-- Streamlined core logic with unified timer management

local M        = require("colorful-times")
local uv       = vim.uv

local system_mod
local state_mod
local theme_resolution_mod

local function theme_resolution()
  theme_resolution_mod = theme_resolution_mod or require("colorful-times.theme_resolution")
  return theme_resolution_mod
end

local function system()
  system_mod = system_mod or require("colorful-times.system")
  return system_mod
end

local function state()
  state_mod = state_mod or require("colorful-times.state")
  return state_mod
end

-- ─── Constants ───────────────────────────────────────────────────────────────
local MS_PER_MINUTE = 60000

-- ─── Module State ────────────────────────────────────────────────────────────
local _timers = {}      -- { schedule = uv_timer|nil, poll = uv_timer|nil }
local _previous_bg
local _focused = true
local _augroup = vim.api.nvim_create_augroup("ColorfulTimes", { clear = true })
local _base_config = nil      -- User config before persisted state is merged
local _poll_inflight = false
local _runtime = M.runtime or { session_pin = nil }
M.runtime = _runtime

-- Static validation lookup tables
local VALID_BACKGROUNDS = { light = true, dark = true, system = true }
local THEME_KEYS = { "light", "dark" }

-- ─── Timer Utilities ───────────────────────────────────────────────────────────

---Stop and close a timer safely
---@param t uv_timer_t|nil
local function stop_timer(t)
  if t and not t:is_closing() then
    t:stop()
    t:close()
  end
end

---Stop all timers
local function stop_all_timers()
  stop_timer(_timers.schedule); _timers.schedule = nil
  stop_timer(_timers.poll);     _timers.poll = nil
end

---Get current time in minutes since midnight (local wall-clock)
---@return integer
local function now_mins()
  local t = os.date("*t")
  return t.hour * 60 + t.min
end

-- ─── Theme Resolution ────────────────────────────────────────────────────────

local function known_resolved_background()
  local bg = _previous_bg or vim.o.background
  return bg == "light" and "light" or "dark"
end

local function runtime_plan()
  return theme_resolution().runtime_plan({
    config = M.config,
    session_hold = _runtime.session_pin,
    now_minute = now_mins(),
    known_resolved_background = known_resolved_background(),
  })
end

---Apply colorscheme and background synchronously
---@param target table
local function apply_sync(target)
  _previous_bg = target.resolved_background
  vim.o.background = target.resolved_background
  pcall(vim.cmd.colorscheme, target.colorscheme)
end

local function apply_when_safe(target)
  vim.schedule(function() apply_sync(target) end)
end

---Apply theme with optional async system detection
function M.apply_colorscheme()
  local plan = runtime_plan()
  apply_when_safe(plan.target)

  if plan.detection.kind ~= "system_background" then
    return
  end

  local detection_plan = system().detection_plan()
  system().run_detection_plan(detection_plan, function(detected)
    local target = plan.detection.targets and plan.detection.targets[detected]
    if target and target.resolved_background ~= _previous_bg then
      apply_when_safe(target)
    end
  end, plan.detection.fallback)
end

---@class ColorfulTimes.Status
---@field enabled boolean
---@field persist boolean
---@field source string
---@field colorscheme string
---@field background string
---@field requested_background string
---@field pinned boolean
---@field session_pin table|nil
---@field schedule_entries integer
---@field refresh_time integer
---@field detection ColorfulTimes.DetectionInfo

---Describe the current resolved theme state for status/reporting.
---@return ColorfulTimes.Status
function M.status()
  local plan = runtime_plan()
  local target = plan.target

  return {
    enabled = M.config.enabled,
    persist = M.config.persist,
    source = target.source,
    colorscheme = target.colorscheme,
    background = target.resolved_background,
    requested_background = target.requested_background,
    pinned = target.session_hold or false,
    session_pin = _runtime.session_pin and vim.deepcopy(_runtime.session_pin) or nil,
    schedule_entries = #M.config.schedule,
    refresh_time = M.config.refresh_time,
    detection = system().detection_info(),
  }
end

---Build the subset of config that is safe to persist.
---@return table
local function persisted_state()
  return {
    enabled = M.config.enabled,
    schedule = vim.deepcopy(M.config.schedule),
    refresh_time = M.config.refresh_time,
    persist = M.config.persist,
    tui_colors = M.config.tui_colors,
    default = vim.deepcopy(M.config.default),
  }
end

---Save the current persisted state when persistence is enabled.
function M.save_state()
  if not M.config.persist then
    return
  end
  state().save(persisted_state())
end

---Merge persisted state from disk on top of the current config.
---@return boolean loaded
local function load_persisted_state()
  if not M.config.persist then
    return false
  end

  local stored = state().load()
  if type(stored) ~= "table" or not next(stored) then
    return false
  end

  local valid, err = state().validate_state(stored)
  if not valid then
    vim.notify("colorful-times: invalid persisted state ignored: " .. (err or "unknown"), vim.log.levels.WARN)
    return false
  end

  M.config = state().merge(M.config, stored)
  return true
end

-- ─── Scheduling ──────────────────────────────────────────────────────────────

---Arm the schedule boundary timer
local start_poll_timer

---Arm the schedule boundary timer
local function arm_schedule_timer()
  stop_timer(_timers.schedule)
  local plan = runtime_plan()
  if not plan.next_schedule_boundary then return end

  _timers.schedule = uv.new_timer()
  _timers.schedule:start(plan.next_schedule_boundary.in_minutes * MS_PER_MINUTE, 0, vim.schedule_wrap(function()
    M.apply_colorscheme()
    arm_schedule_timer()
    start_poll_timer()
  end))
end

---Start the system background poll timer
start_poll_timer = function()
  stop_timer(_timers.poll)
  _poll_inflight = false

  local plan = runtime_plan()
  if not plan.poll_needed then return end
  local detection_plan = system().detection_plan()
  if not detection_plan.available then return end

  local fallback = plan.detection.fallback or _previous_bg or "dark"
  _timers.poll = uv.new_timer()
  _timers.poll:start(0, M.config.refresh_time, function()
    if not _focused then return end
    if _poll_inflight then return end

    _poll_inflight = true
    system().run_detection_plan(detection_plan, function(bg)
      _poll_inflight = false
      if bg ~= _previous_bg then M.apply_colorscheme() end
    end, fallback)
  end)
end

---Re-apply current config and restart runtime timers without reloading persisted state.
function M.refresh()
  stop_all_timers()
  _poll_inflight = false

  M.apply_colorscheme()
  if M.config.enabled then
    arm_schedule_timer()
    start_poll_timer()
  end
end

---@return table|nil
function M.session_pin()
  return _runtime.session_pin and vim.deepcopy(_runtime.session_pin) or nil
end

---@param colorscheme? string
---@param background? "light"|"dark"|"system"
---@param resolved_background? "light"|"dark"
function M.pin_session(colorscheme, background, resolved_background)
  local cs = colorscheme or vim.g.colors_name or M.config.default.colorscheme
  local requested_bg = VALID_BACKGROUNDS[background] and background or (vim.o.background or "dark")
  local concrete_bg = resolved_background

  if concrete_bg ~= "light" and concrete_bg ~= "dark" then
    concrete_bg = requested_bg ~= "system" and requested_bg or (_previous_bg or vim.o.background or "dark")
  end
  if concrete_bg ~= "light" and concrete_bg ~= "dark" then
    concrete_bg = "dark"
  end

  _runtime.session_pin = {
    colorscheme = cs,
    background = requested_bg,
    resolved_background = concrete_bg,
  }
  _previous_bg = concrete_bg
  M.refresh()
end

function M.unpin_session()
  if not _runtime.session_pin then
    return
  end
  _runtime.session_pin = nil
  M.refresh()
end

-- ─── Enable / Disable ────────────────────────────────────────────────────────

function M.enable()
  local changed = not M.config.enabled
  M.config.enabled = true
  if changed then
    M.save_state()
  end

  stop_all_timers()
  M.apply_colorscheme()
  arm_schedule_timer()
  start_poll_timer()
  vim.notify("colorful-times: enabled", vim.log.levels.INFO)
end

function M.disable()
  local changed = M.config.enabled
  M.config.enabled = false
  if changed then
    M.save_state()
  end

  stop_all_timers()
  M.apply_colorscheme()  -- Apply with enabled=false for default
  vim.notify("colorful-times: disabled", vim.log.levels.INFO)
end

function M.toggle()
  if M.config.enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.toggle_tui_colors()
  M.config.tui_colors = M.config.tui_colors == "theme" and "default" or "theme"
  M.save_state()
  return M.config.tui_colors
end

function M.runtime_plan()
  return runtime_plan()
end

---@param req table
---@return table
function M.preview_target(req)
  req = vim.deepcopy(req or {})
  req.config = req.config or M.config
  req.now_minute = req.now_minute or now_mins()
  req.known_resolved_background = req.known_resolved_background or known_resolved_background()
  return theme_resolution().preview_target(req)
end

function M.reload()
  stop_all_timers()
  _previous_bg = nil
  _poll_inflight = false

  if _base_config then
    M.config = vim.deepcopy(_base_config)
  end
  load_persisted_state()

  M.apply_colorscheme()
  if M.config.enabled then
    arm_schedule_timer()
    start_poll_timer()
  end
end

-- ─── Setup ───────────────────────────────────────────────────────────────────

---Validate schedule time without loading the full schedule module during setup.
---@param value unknown
---@return integer|nil
local function validate_time(value)
  if type(value) ~= "string" then return nil end
  local hour, min = value:match("^(%d%d?):(%d%d)$")
  if not hour then return nil end
  hour, min = tonumber(hour), tonumber(min)
  if hour >= 24 or min >= 60 then return nil end
  return hour * 60 + min
end

---Validate one schedule entry without loading the full schedule module during setup.
---@param entry unknown
---@return boolean ok
---@return string? error
local function validate_schedule_entry(entry)
  if type(entry) ~= "table" then
    return false, "entry must be a table"
  end

  if type(entry.colorscheme) ~= "string" or entry.colorscheme == "" then
    return false, "missing colorscheme"
  end

  local start_time = validate_time(entry.start)
  if not start_time then
    return false, "invalid start time: " .. tostring(entry.start)
  end

  local stop_time = validate_time(entry.stop)
  if not stop_time then
    return false, "invalid stop time: " .. tostring(entry.stop)
  end

  if start_time == stop_time then
    return false, "start and stop times must differ: " .. tostring(entry.start)
  end

  if entry.background ~= nil then
    if type(entry.background) ~= "string" or not VALID_BACKGROUNDS[entry.background] then
      return false, "invalid background: " .. tostring(entry.background)
    end
  end

  return true
end

---Validate user options
---@param opts table
---@return boolean ok
---@return string? error
local function validate(opts)
  if opts.enabled ~= nil and type(opts.enabled) ~= "boolean" then
    return false, "enabled must be a boolean"
  end

  if opts.refresh_time ~= nil then
    if type(opts.refresh_time) ~= "number" or opts.refresh_time < 1000 then
      return false, "refresh_time must be an integer >= 1000"
    end
  end

  if opts.persist ~= nil and type(opts.persist) ~= "boolean" then
    return false, "persist must be a boolean"
  end

  if opts.tui_colors ~= nil then
    if type(opts.tui_colors) ~= "string" or (opts.tui_colors ~= "default" and opts.tui_colors ~= "theme") then
      return false, "tui_colors must be 'default' or 'theme'"
    end
  end

  if opts.schedule ~= nil then
    if type(opts.schedule) ~= "table" then
      return false, "schedule must be an array"
    end
    for i, entry in ipairs(opts.schedule) do
      local ok, err = validate_schedule_entry(entry)
      if not ok then return false, string.format("schedule[%d]: %s", i, err) end
    end
  end

  if opts.default and opts.default.background then
    if not VALID_BACKGROUNDS[opts.default.background] then
      return false, "background must be 'light', 'dark', or 'system'"
    end
  end

  if opts.default and opts.default.colorscheme ~= nil and type(opts.default.colorscheme) ~= "string" then
    return false, "default.colorscheme must be a string"
  end

  if opts.default and opts.default.themes ~= nil then
    if type(opts.default.themes) ~= "table" then
      return false, "default.themes must be a table"
    end

    for _, key in ipairs(THEME_KEYS) do
      local theme = opts.default.themes[key]
      if theme ~= nil and type(theme) ~= "string" then
        return false, "default.themes." .. key .. " must be a string"
      end
    end
  end

  return true
end

---@param opts ColorfulTimes.Config?
function M.setup(opts)
  if opts then
    local ok, err = validate(opts)
    if not ok then
      vim.notify("colorful-times: " .. err, vim.log.levels.ERROR)
      return
    end

    local safe = vim.deepcopy(opts, true)
    if safe.default then
      M.config.default = vim.tbl_deep_extend("force", M.config.default, safe.default)
      safe.default = nil
    end
    for k, v in pairs(safe) do
      M.config[k] = v
    end

  end

  _base_config = vim.deepcopy(M.config)

  -- Register focus autocmds unconditionally (toggle needs them later)
  vim.api.nvim_clear_autocmds({ group = _augroup })
  vim.api.nvim_create_autocmd("FocusLost", {
    group = _augroup,
    callback = function() _focused = false end,
  })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = _augroup,
    callback = function()
      _focused = true
      local plan = runtime_plan()
      if plan.poll_needed then
        system().run_detection_plan(system().detection_plan(), function(bg)
          if bg ~= _previous_bg then M.apply_colorscheme() end
          start_poll_timer()
        end, plan.detection.fallback or _previous_bg or "dark")
      end
    end,
  })

  vim.defer_fn(function()
    load_persisted_state()
    if not M.config.enabled then
      return
    end

    M.apply_colorscheme()
    arm_schedule_timer()
    start_poll_timer()
  end, 0)
end

-- TUI entry point
function M.open()
  require("colorful-times.tui").open()
end

return M
