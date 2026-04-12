-- plugin/colorful-times.lua
-- Loaded automatically by Neovim at startup via the plugin/ directory.
-- Must be fast: only registers commands, no heavy requires.

vim.api.nvim_create_user_command("ColorfulTimes", function()
  require("colorful-times.core")
  require("colorful-times").open()
end, { desc = "Open colorful-times schedule manager" })

vim.api.nvim_create_user_command("ColorfulTimesEnable", function()
  require("colorful-times.core")
  require("colorful-times").enable()
end, { desc = "Enable colorful-times" })

vim.api.nvim_create_user_command("ColorfulTimesDisable", function()
  require("colorful-times.core")
  require("colorful-times").disable()
end, { desc = "Disable colorful-times" })

vim.api.nvim_create_user_command("ColorfulTimesToggle", function()
  require("colorful-times.core")
  require("colorful-times").toggle()
end, { desc = "Toggle colorful-times on/off" })

vim.api.nvim_create_user_command("ColorfulTimesReload", function()
  require("colorful-times.core")
  require("colorful-times").reload()
end, { desc = "Reload colorful-times configuration" })

vim.api.nvim_create_user_command("ColorfulTimesStatus", function()
  require("colorful-times.core")
  local status = require("colorful-times").status()

  vim.notify(table.concat({
    "colorful-times status:",
    "  enabled: " .. tostring(status.enabled),
    "  persist: " .. tostring(status.persist),
    "  source: " .. status.source,
    "  colorscheme: " .. status.colorscheme,
    "  background: " .. status.background,
    "  requested background: " .. status.requested_background,
    "  schedule entries: " .. tostring(status.schedule_entries),
    "  refresh_time: " .. tostring(status.refresh_time) .. "ms",
    "  detection: " .. status.detection.detail,
  }, "\n"), vim.log.levels.INFO)
end, { desc = "Show colorful-times status" })
