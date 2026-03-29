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

---Get current time in minutes since midnight
---@return integer
local function now_mins()
  local d = os.date("*t")
  return d.hour * 60 + d.min
end

-- ─── Theme Resolution ────────────────────────────────────────────────────────

---Resolve current theme based on config and schedule
---@return string colorscheme
---@return string background
function M.resolve_theme()
  local cfg = M.config
  if not cfg.enabled then
    local bg = cfg.default.background
    local cs = bg ~= "system" and cfg.default.themes[bg] or cfg.default.colorscheme
    return cs or cfg.default.colorscheme, bg
  end
  
  -- Use cached parsed schedule for better performance
  local current_mins = now_mins()
  _parsed_schedule = _parsed_schedule or schedule.preprocess(cfg.schedule, cfg.default.background)
  local active = schedule.get_active_entry(_parsed_schedule, current_mins)
  
  if active then
    return active.colorscheme, active.background
  end
  
  local bg = cfg.default.background
  local cs = bg ~= "system" and cfg.default.themes[bg] or cfg.default.colorscheme
  return cs or cfg.default.colorscheme, bg
end

---Apply colorscheme and background synchronously
---@param cs string
---@param bg string
local function apply_sync(cs, bg)
  _previous_bg = bg
  vim.o.background = bg
  pcall(vim.cmd.colorscheme, cs)
end

---Apply theme with optional async system detection
function M.apply_colorscheme()
  local cs, bg = M.resolve_theme()
  
  if bg ~= "system" then
    vim.schedule(function() apply_sync(cs, bg) end)
    return
  end
  
  -- System background: apply fallback first, then detect
  local fallback = _previous_bg or vim.o.background or "dark"
  local fallback_cs = M.config.default.themes[fallback] or cs
  
  vim.schedule(function() apply_sync(fallback_cs, fallback) end)
  
  system.get_background(function(detected)
    if detected ~= _previous_bg then
      local real_cs = M.config.default.themes[detected] or cs
      vim.schedule(function() apply_sync(real_cs, detected) end)
    end
  end, fallback)
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
  end))
end

---Start the system background poll timer
local function start_poll_timer()
  stop_timer(_timers.poll)
  
  if not needs_system_poll() then return end
  if not system.has_detection() then return end
  
  local fallback = _previous_bg or "dark"
  _timers.poll = uv.new_timer()
  _timers.poll:start(0, M.config.refresh_time, function()
    if not _focused then return end
    system.get_background(function(bg)
      if bg ~= _previous_bg then M.apply_colorscheme() end
    end, fallback)
  end)
end

-- ─── Enable / Disable ──────────────────────────────────────────────────────────

function M.enable()
  M.apply_colorscheme()
  arm_schedule_timer()
  start_poll_timer()
  vim.notify("colorful-times: enabled", vim.log.levels.INFO)
end

function M.disable()
  stop_all_timers()
  M.apply_colorscheme()  -- Apply with enabled=false for default
  vim.notify("colorful-times: disabled", vim.log.levels.INFO)
end

function M.toggle()
  M.config.enabled = not M.config.enabled
  if M.config.enabled then M.enable() else M.disable() end
end

function M.reload()
  stop_all_timers()
  _previous_bg = nil
  _parsed_schedule = nil  -- Clear schedule cache
  M.apply_colorscheme()
  arm_schedule_timer()
  start_poll_timer()
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
    local valid = { light = true, dark = true, system = true }
    if not valid[opts.default.background] then
      return false, "background must be 'light', 'dark', or 'system'"
    end
  end
  
  return true
end

---@param opts ColorfulTimes.Config?
function M.setup(opts)
  -- Load persisted state first (base layer)
  local stored = state.load()
  if type(stored) == "table" and next(stored) then
    M.config = state.merge(M.config, stored)
  end
  
  -- Merge user opts on top (user wins)
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
    -- Use 'force' to overwrite everything including refresh_time
    for k, v in pairs(safe) do
      M.config[k] = v
    end
    
    -- Clear schedule cache when config changes
    _parsed_schedule = nil
  end
  
  -- Register focus autocmds
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
        end, _previous_bg or "dark")
      end
    end,
  })
  
  if M.config.enabled then M.enable() end
end

-- TUI entry point
function M.open()
  require("colorful-times.tui").open()
end

return M
