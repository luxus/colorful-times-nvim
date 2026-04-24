-- lua/colorful-times/init.lua
--- Modern, streamlined ColorfulTimes plugin
---@class ColorfulTimes
local M = {}

---@class ColorfulTimes.ScheduleEntry
---@field start string          Start time "HH:MM"
---@field stop string           Stop time "HH:MM"
---@field colorscheme string    Colorscheme name
---@field background? string    "light" | "dark" | "system" | nil

---@class ColorfulTimes.ParsedEntry
---@field start_time integer    Minutes since midnight
---@field stop_time integer     Minutes since midnight
---@field colorscheme string
---@field background string

---@class ColorfulTimes.ThemeConfig
---@field light? string
---@field dark? string

---@class ColorfulTimes.DefaultConfig
---@field colorscheme string
---@field background "light" | "dark" | "system"
---@field themes ColorfulTimes.ThemeConfig

---@class ColorfulTimes.Config
---@field enabled boolean
---@field refresh_time integer
---@field system_background_detection? string[]|fun():string
---@field system_background_detection_script? string
---@field default ColorfulTimes.DefaultConfig
---@field schedule ColorfulTimes.ScheduleEntry[]
---@field persist boolean

M.config = {
  enabled = true,
  refresh_time = 5000,
  system_background_detection = nil,
  system_background_detection_script = nil,
  default = {
    colorscheme = "default",
    background = "system",
    themes = { light = nil, dark = nil },
  },
  schedule = {},
  persist = true,
}

-- Lazy-load core on first access - use static lookup for O(1) check
local _loaded = false
local _lazy_keys = {
  setup = true,
  enable = true,
  disable = true,
  toggle = true,
  reload = true,
  open = true,
  status = true,
  apply_colorscheme = true,
  refresh = true,
  resolve_theme_context = true,
  active_resolved_theme = true,
  pin_session = true,
  unpin_session = true,
  session_pin = true,
}

local function ensure_loaded()
  if not _loaded then
    _loaded = true
    require("colorful-times.core")
  end
end

setmetatable(M, {
  __index = function(t, key)
    if _lazy_keys[key] then
      ensure_loaded()
      return t[key]
    end
  end,
})

return M
