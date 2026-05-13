-- lua/colorful-times/theme_resolution.lua
-- Theme resolution policy for runtime application and TUI preview targets.

local M = {}

local VALID_REQUESTED = { light = true, dark = true, system = true }
local VALID_RESOLVED = { light = true, dark = true }
local MINUTES_PER_DAY = 1440

local schedule_mod

local function schedule()
  schedule_mod = schedule_mod or require("colorful-times.schedule_runtime")
  return schedule_mod
end

local function normalize_resolved_background(value)
  if value == "light" or value == "dark" then
    return value
  end
  error("known_resolved_background must be 'light' or 'dark'", 3)
end

local function normalize_requested_background(value, fallback)
  if VALID_REQUESTED[value] then
    return value
  end
  if VALID_REQUESTED[fallback] then
    return fallback
  end
  return "dark"
end

local function default_colorscheme(config, resolved_background)
  local default = config.default or {}
  local themes = default.themes or {}
  return themes[resolved_background] or default.colorscheme or "default"
end

local function make_target(base, requested_background, known_resolved_background)
  requested_background = normalize_requested_background(requested_background, "dark")
  local resolved_background = requested_background == "system" and known_resolved_background or requested_background

  local colorscheme = base.colorscheme
  if base.source == "default" then
    colorscheme = default_colorscheme(base.config, resolved_background)
  end

  return {
    colorscheme = colorscheme or default_colorscheme(base.config, resolved_background),
    requested_background = requested_background,
    resolved_background = resolved_background,
    source = base.source,
    session_hold = base.session_hold or false,
  }
end

local function default_base(config)
  local default = config.default or {}
  return {
    config = config,
    source = "default",
    colorscheme = default.colorscheme or "default",
    requested_background = normalize_requested_background(default.background, "dark"),
  }
end

local function session_hold_base(config, session_hold)
  return {
    config = config,
    source = "session_hold",
    colorscheme = session_hold.colorscheme,
    requested_background = normalize_requested_background(session_hold.background, "dark"),
    resolved_background = session_hold.resolved_background,
    session_hold = true,
  }
end

local function active_schedule_base(config, now_minute)
  if not config.enabled or type(config.schedule) ~= "table" or #config.schedule == 0 then
    return nil, nil
  end

  local sched = schedule()
  local parsed = sched.preprocess(config.schedule, config.default and config.default.background or "dark")
  local active = sched.get_active_entry(parsed, now_minute)
  if not active then
    return nil, parsed
  end

  return {
    config = config,
    source = "schedule",
    colorscheme = active.colorscheme,
    requested_background = normalize_requested_background(active.background, config.default and config.default.background or "dark"),
  }, parsed
end

local function next_schedule_boundary(config, parsed, now_minute)
  if not config.enabled or type(config.schedule) ~= "table" or #config.schedule == 0 then
    return nil
  end

  parsed = parsed or schedule().preprocess(config.schedule, config.default and config.default.background or "dark")
  local diff = schedule().next_change_at(parsed, now_minute)
  if not diff then
    return nil
  end

  return {
    in_minutes = diff,
    at_minute = (now_minute + diff) % MINUTES_PER_DAY,
  }
end

local function select_base(config, now_minute, session_hold)
  if session_hold then
    return session_hold_base(config, session_hold), nil
  end

  local active, parsed = active_schedule_base(config, now_minute)
  if active then
    return active, parsed
  end

  return default_base(config), parsed
end

local function detection_intent(base, known_resolved_background)
  local requested = normalize_requested_background(base.requested_background, "dark")
  if requested ~= "system" or base.session_hold then
    return { kind = "none" }
  end

  return {
    kind = "system_background",
    fallback = known_resolved_background,
    targets = {
      light = make_target(base, requested, "light"),
      dark = make_target(base, requested, "dark"),
    },
  }
end

---@param req table
---@return table
function M.runtime_plan(req)
  if type(req) ~= "table" then
    error("runtime_plan request must be a table", 2)
  end

  local config = req.config or {}
  local now_minute = req.now_minute or 0
  local known = normalize_resolved_background(req.known_resolved_background)
  local base, parsed = select_base(config, now_minute, req.session_hold)

  local target
  if base.session_hold and VALID_RESOLVED[base.resolved_background] then
    target = make_target(base, base.requested_background, base.resolved_background)
  else
    target = make_target(base, base.requested_background, known)
  end

  local detection = detection_intent(base, known)

  return {
    target = target,
    detection = detection,
    poll_needed = detection.kind == "system_background",
    next_schedule_boundary = (not base.session_hold) and next_schedule_boundary(config, parsed, now_minute) or nil,
  }
end

local function preview_base(config, draft, draft_kind)
  if draft then
    if draft_kind == "default_colorscheme" or draft_kind == "default_background" or draft_kind == "default_light" or draft_kind == "default_dark" then
      local default = vim.deepcopy(config.default or {})
      default.themes = default.themes or {}

      if draft_kind == "default_colorscheme" then
        default.colorscheme = draft.colorscheme or default.colorscheme
      elseif draft_kind == "default_background" then
        default.background = normalize_requested_background(draft.background, default.background)
      elseif draft_kind == "default_light" then
        default.themes.light = draft.colorscheme
        default.background = "light"
      elseif draft_kind == "default_dark" then
        default.themes.dark = draft.colorscheme
        default.background = "dark"
      end

      return default_base({ default = default, enabled = false, schedule = {} })
    end

    return {
      config = config,
      source = "schedule",
      colorscheme = draft.colorscheme,
      requested_background = normalize_requested_background(draft.background, config.default and config.default.background or "dark"),
    }
  end

  return select_base(config, 0, nil)
end

---@param req table
---@return table
function M.preview_target(req)
  if type(req) ~= "table" then
    error("preview_target request must be a table", 2)
  end

  local config = req.config or {}
  local known = normalize_resolved_background(req.known_resolved_background)
  local base

  if req.draft then
    base = preview_base(config, req.draft, req.draft_kind)
  else
    base = select_base(config, req.now_minute or 0, nil)
  end

  return make_target(base, base.requested_background, known)
end

return M
