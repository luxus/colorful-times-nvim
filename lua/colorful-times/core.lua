-- lua/colorful-times/core.lua
-- Streamlined core logic with unified timer management

local M        = require("colorful-times")
local uv       = vim.uv

local schedule_mod
local system_mod
local state_mod

local function schedule()
  schedule_mod = schedule_mod or require("colorful-times.schedule")
  return schedule_mod
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
local _parsed_schedule = nil  -- Cache for preprocessed schedule
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

---Resolve current theme as scalar values for hot paths.
---@return string colorscheme
---@return string background
---@return boolean use_default_theme_overrides
---@return string source
---@return boolean pinned
---@return string? resolved_background
---@return table? session_pin
local function resolve_theme_parts()
  local pin = _runtime.session_pin
  if pin then
    return pin.colorscheme, pin.background, false, "session_pin", true, pin.resolved_background, pin
  end

  local cfg = M.config
  if not cfg.enabled then
    local bg = cfg.default.background
    local cs = bg ~= "system" and cfg.default.themes[bg] or cfg.default.colorscheme
    return cs or cfg.default.colorscheme, bg, true, "default", false
  end

  local current_mins = now_mins()
  local sched = schedule()
  _parsed_schedule = _parsed_schedule or sched.preprocess(cfg.schedule, cfg.default.background)
  local active = sched.get_active_entry(_parsed_schedule, current_mins)

  if active then
    return active.colorscheme, active.background, false, "schedule", false
  end

  local bg = cfg.default.background
  local cs = bg ~= "system" and cfg.default.themes[bg] or cfg.default.colorscheme
  return cs or cfg.default.colorscheme, bg, true, "default", false
end

---Resolve current theme based on config and schedule
---@return table
local function resolve_theme_context()
  local cs, bg, use_default_theme_overrides, source, pinned, resolved_background, pin = resolve_theme_parts()
  local context = {
    source = source,
    colorscheme = cs,
    background = bg,
    use_default_theme_overrides = use_default_theme_overrides,
  }
  if pinned then
    context.resolved_background = resolved_background
    context.pinned = true
    context.session_pin = vim.deepcopy(pin)
  end
  return context
end

---Resolve current theme based on config and schedule
---@return string colorscheme
---@return string background
---@return boolean use_default_theme_overrides
function M.resolve_theme()
  local cs, bg, use_default_theme_overrides = resolve_theme_parts()
  return cs, bg, use_default_theme_overrides
end

---@return table
function M.resolve_theme_context()
  return vim.deepcopy(resolve_theme_context())
end

---@return string colorscheme
---@return string background
function M.active_resolved_theme()
  local status = M.status()
  return status.colorscheme, status.background
end

---Apply colorscheme and background synchronously
---@param cs string
---@param bg string
local function apply_sync(cs, bg)
  _previous_bg = bg
  vim.o.background = bg
  pcall(vim.cmd.colorscheme, cs)
end

local function apply_when_safe(cs, bg)
  vim.schedule(function() apply_sync(cs, bg) end)
end

---Resolve a colorscheme for a detected light/dark background.
---@param base_cs string
---@param detected_bg "light"|"dark"
---@param use_default_theme_overrides boolean
---@return string
local function resolve_detected_colorscheme(base_cs, detected_bg, use_default_theme_overrides)
  if use_default_theme_overrides then
    local themed = M.config.default.themes[detected_bg]
    if themed then
      return themed
    end
  end
  return base_cs
end

---Apply theme with optional async system detection
function M.apply_colorscheme()
  local cs, bg, use_default_theme_overrides, _, pinned, resolved_background = resolve_theme_parts()

  if pinned then
    local concrete_bg = resolved_background
    if concrete_bg ~= "light" and concrete_bg ~= "dark" then
      concrete_bg = bg ~= "system" and bg or (_previous_bg or vim.o.background or "dark")
    end
    apply_when_safe(cs, concrete_bg)
    return
  end

  if bg ~= "system" then
    apply_when_safe(cs, bg)
    return
  end

  -- System background: apply fallback first, then detect
  local fallback = _previous_bg or vim.o.background or "dark"
  local fallback_cs = resolve_detected_colorscheme(cs, fallback, use_default_theme_overrides)

  apply_when_safe(fallback_cs, fallback)

  system().get_background(function(detected)
    if detected ~= _previous_bg then
      local real_cs = resolve_detected_colorscheme(cs, detected, use_default_theme_overrides)
      apply_when_safe(real_cs, detected)
    end
  end, fallback)
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
  local resolved = resolve_theme_context()
  local effective_bg = resolved.background
  local effective_cs = resolved.colorscheme

  if resolved.pinned then
    effective_bg = resolved.resolved_background or resolved.background or vim.o.background or "dark"
  elseif resolved.background == "system" then
    effective_bg = _previous_bg or vim.o.background or "dark"
    effective_cs = resolve_detected_colorscheme(
      resolved.colorscheme,
      effective_bg,
      resolved.use_default_theme_overrides
    )
  end

  return {
    enabled = M.config.enabled,
    persist = M.config.persist,
    source = resolved.source,
    colorscheme = effective_cs,
    background = effective_bg,
    requested_background = resolved.background,
    pinned = resolved.pinned or false,
    session_pin = resolved.session_pin,
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
  _parsed_schedule = nil
  return true
end

-- ─── Scheduling ──────────────────────────────────────────────────────────────

---Check if system polling is needed based on current schedule
---@return boolean
local function needs_system_poll()
  if _runtime.session_pin then
    return false
  end

  if not M.config.enabled then
    return M.config.default.background == "system"
  end

  local current_mins = now_mins()
  local sched = schedule()
  _parsed_schedule = _parsed_schedule or sched.preprocess(M.config.schedule, M.config.default.background)
  local active = sched.get_active_entry(_parsed_schedule, current_mins)
  return (active and active.background or M.config.default.background) == "system"
end

---Arm the schedule boundary timer
local start_poll_timer

---Arm the schedule boundary timer
local function arm_schedule_timer()
  stop_timer(_timers.schedule)
  if not M.config.enabled then return end

  -- Use cached parsed schedule for efficiency
  local sched = schedule()
  _parsed_schedule = _parsed_schedule or sched.preprocess(M.config.schedule, M.config.default.background)
  local diff = sched.next_change_at(_parsed_schedule, now_mins())
  if not diff then return end

  _timers.schedule = uv.new_timer()
  _timers.schedule:start(diff * MS_PER_MINUTE, 0, vim.schedule_wrap(function()
    M.apply_colorscheme()
    arm_schedule_timer()
    start_poll_timer()
  end))
end

---Start the system background poll timer
start_poll_timer = function()
  stop_timer(_timers.poll)
  _poll_inflight = false

  if not needs_system_poll() then return end
  if not system().has_detection() then return end

  local fallback = _previous_bg or "dark"
  _timers.poll = uv.new_timer()
  _timers.poll:start(0, M.config.refresh_time, function()
    if not _focused then return end
    if _poll_inflight then return end

    _poll_inflight = true
    system().get_background(function(bg)
      _poll_inflight = false
      if bg ~= _previous_bg then M.apply_colorscheme() end
    end, fallback)
  end)
end

---Re-apply current config and restart runtime timers without reloading persisted state.
function M.refresh()
  stop_all_timers()
  _parsed_schedule = nil
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

function M.reload()
  stop_all_timers()
  _previous_bg = nil
  _parsed_schedule = nil  -- Clear schedule cache
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

  if opts.schedule ~= nil then
    if type(opts.schedule) ~= "table" then
      return false, "schedule must be an array"
    end
    for i = 1, #opts.schedule do
      local ok, err = validate_schedule_entry(opts.schedule[i])
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

    _parsed_schedule = nil
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
      if needs_system_poll() then
        system().get_background(function(bg)
          if bg ~= _previous_bg then M.apply_colorscheme() end
          start_poll_timer()
        end, _previous_bg or "dark")
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
