-- lua/colorful-times/init.lua

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
---@field light string|nil
---@field dark string|nil

---@class ColorfulTimes.DefaultConfig
---@field colorscheme string
---@field background string     "light" | "dark" | "system"
---@field themes ColorfulTimes.ThemeConfig

---@class ColorfulTimes.Config
---@field enabled boolean
---@field refresh_time integer  Milliseconds between appearance polls
---@field system_background_detection string[]|fun():string|nil
---@field default ColorfulTimes.DefaultConfig
---@field schedule ColorfulTimes.ScheduleEntry[]
---@field persist boolean       Whether TUI changes are written to state.json

M.config = {
  enabled = true,
  refresh_time = 5000,  -- DEFAULT_REFRESH_TIME (ms): poll interval for system background changes
  system_background_detection = nil,
  default = {
    colorscheme = "default",
    background = "system",
    themes = { light = nil, dark = nil },
  },
  schedule = {},
  persist = true,
}

-- Lazy-load core on first access of setup/toggle/reload/open
local _lazy_fns = { "setup", "toggle", "reload", "open" }
setmetatable(M, {
  __index = function(_, key)
    if vim.tbl_contains(_lazy_fns, key) then
      require("colorful-times.core")
      return M[key]
    end
  end,
})

return M
