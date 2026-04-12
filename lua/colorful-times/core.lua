-- lua/colorful-times/core.lua
-- Streamlined core logic with unified timer management

local M        = require("colorful-times")
local schedule = require("colorful-times.schedule")
local system   = require("colorful-times.system")
local state    = require("colorful-times.state")
local uv       = vim.uv

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

-- Static validation lookup tables
local VALID_BACKGROUNDS = { light = true, dark = true, system = true }

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

---Resolve current theme based on config and schedule
---@return table
local function resolve_theme_context()
  local cfg = M.config
  if not cfg.enabled then
    local bg = cfg.default.background
    local cs = bg ~= "system" and cfg.default.themes[bg] or cfg.default.colorscheme
    return {
      source = "default",
      colorscheme = cs or cfg.default.colorscheme,
      background = bg,
      use_default_theme_overrides = true,
    }
  end

  local current_mins = now_mins()
  _parsed_schedule = _parsed_schedule or schedule.preprocess(cfg.schedule, cfg.default.background)
  local active = schedule.get_active_entry(_parsed_schedule, current_mins)

  if active then
    return {
      source = "schedule",
      colorscheme = active.colorscheme,
      background = active.background,
      use_default_theme_overrides = false,
    }
  end

  local bg = cfg.default.background
  local cs = bg ~= "system" and cfg.default.themes[bg] or cfg.default.colorscheme
  return {
    source = "default",
    colorscheme = cs or cfg.default.colorscheme,
    background = bg,
    use_default_theme_overrides = true,
  }
end

---Resolve current theme based on config and schedule
---@return string colorscheme
---@return string background
---@return boolean use_default_theme_overrides
function M.resolve_theme()
  local resolved = resolve_theme_context()
  return resolved.colorscheme, resolved.background, resolved.use_default_theme_overrides
end

---Apply colorscheme and background synchronously
---@param cs string
---@param bg string
local function apply_sync(cs, bg)
  _previous_bg = bg
  vim.o.background = bg
  pcall(vim.cmd.colorscheme, cs)
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
  local cs, bg, use_default_theme_overrides = M.resolve_theme()
  
  if bg ~= "system" then
    vim.schedule(function() apply_sync(cs, bg) end)
    return
  end
  
  -- System background: apply fallback first, then detect
  local fallback = _previous_bg or vim.o.background or "dark"
  local fallback_cs = resolve_detected_colorscheme(cs, fallback, use_default_theme_overrides)
  
  vim.schedule(function() apply_sync(fallback_cs, fallback) end)
  
  system.get_background(function(detected)
    if detected ~= _previous_bg then
      local real_cs = resolve_detected_colorscheme(cs, detected, use_default_theme_overrides)
      vim.schedule(function() apply_sync(real_cs, detected) end)
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
---@field schedule_entries integer
---@field refresh_time integer
---@field detection ColorfulTimes.DetectionInfo

---Describe the current resolved theme state for status/reporting.
---@return ColorfulTimes.Status
function M.status()
  local resolved = resolve_theme_context()
  local effective_bg = resolved.background
  local effective_cs = resolved.colorscheme

  if resolved.background == "system" then
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
    schedule_entries = #M.config.schedule,
    refresh_time = M.config.refresh_time,
    detection = system.detection_info(),
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
  state.save(persisted_state())
end

---Merge persisted state from disk on top of the current config.
---@return boolean loaded
local function load_persisted_state()
  if not M.config.persist then
    return false
  end

  local stored = state.load()
  if type(stored) ~= "table" or not next(stored) then
    return false
  end

  local valid, err = state.validate_state(stored)
  if not valid then
    vim.notify("colorful-times: invalid persisted state ignored: " .. (err or "unknown"), vim.log.levels.WARN)
    return false
  end

  M.config = state.merge(M.config, stored)
  _parsed_schedule = nil
  return true
end

-- ─── Scheduling ──────────────────────────────────────────────────────────────

---Check if system polling is needed based on current schedule
---@return boolean
local function needs_system_poll()
  if not M.config.enabled then
    return M.config.default.background == "system"
  end
  
  local current_mins = now_mins()
  _parsed_schedule = _parsed_schedule or schedule.preprocess(M.config.schedule, M.config.default.background)
  local active = schedule.get_active_entry(_parsed_schedule, current_mins)
  return (active and active.background or M.config.default.background) == "system"
end

---Arm the schedule boundary timer
local function arm_schedule_timer()
  stop_timer(_timers.schedule)
  if not M.config.enabled then return end
  
  -- Use cached parsed schedule for efficiency
  _parsed_schedule = _parsed_schedule or schedule.preprocess(M.config.schedule, M.config.default.background)
  local diff = schedule.next_change_at(_parsed_schedule, now_mins())
  if not diff then return end
  
  _timers.schedule = uv.new_timer()
  _timers.schedule:start(diff * MS_PER_MINUTE, 0, vim.schedule_wrap(function()
    M.apply_colorscheme()
    arm_schedule_timer()
    start_poll_timer()
  end))
end

---Start the system background poll timer
local function start_poll_timer()
  stop_timer(_timers.poll)
  _poll_inflight = false
  
  if not needs_system_poll() then return end
  if not system.has_detection() then return end
  
  local fallback = _previous_bg or "dark"
  _timers.poll = uv.new_timer()
  _timers.poll:start(0, M.config.refresh_time, function()
    if not _focused then return end
    if _poll_inflight then return end

    _poll_inflight = true
    system.get_background(function(bg)
      _poll_inflight = false
      if bg ~= _previous_bg then M.apply_colorscheme() end
    end, fallback)
  end)
end

-- ─── Enable / Disable ──────────────────────────────────────────────────────────

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
    for i, entry in ipairs(opts.schedule) do
      local ok, err = schedule.validate_entry(entry)
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

    for _, key in ipairs({ "light", "dark" }) do
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

    local safe = vim.deepcopy(opts)
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
        system.get_background(function(bg)
          if bg ~= _previous_bg then M.apply_colorscheme() end
          start_poll_timer()
        end, _previous_bg or "dark")
      end
    end,
  })

  if not M.config.enabled then return end

  vim.defer_fn(function()
    load_persisted_state()

    M.apply_colorscheme()
    if M.config.enabled then
      arm_schedule_timer()
      start_poll_timer()
    end
  end, 0)
end

-- TUI entry point
function M.open()
  require("colorful-times.tui").open()
end

return M
