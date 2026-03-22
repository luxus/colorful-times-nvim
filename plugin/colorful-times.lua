-- plugin/colorful-times.lua
-- Loaded automatically by Neovim at startup via the plugin/ directory.
-- Must be fast: only registers commands, no heavy requires.

vim.api.nvim_create_user_command("ColorfulTimes", function()
  require("colorful-times.core")
  require("colorful-times").open()
end, { desc = "Open colorful-times schedule manager" })

vim.api.nvim_create_user_command("ColorfulTimesToggle", function()
  require("colorful-times.core")
  require("colorful-times").toggle()
end, { desc = "Toggle colorful-times on/off" })

vim.api.nvim_create_user_command("ColorfulTimesReload", function()
  require("colorful-times.core")
  require("colorful-times").reload()
end, { desc = "Reload colorful-times configuration" })
