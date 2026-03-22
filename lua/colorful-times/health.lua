-- lua/colorful-times/health.lua
local M = {}

function M.check()
  local health = vim.health

  -- Neovim version check
  if vim.fn.has("nvim-0.12") == 1 then
    health.ok("Neovim >= 0.12")
  else
    health.error("Neovim >= 0.12 required (found " .. tostring(vim.version()) .. ")")
  end

  -- vim.uv availability
  if vim.uv then
    health.ok("vim.uv available")
  else
    health.error("vim.uv not available — this should not happen on Neovim 0.12+")
  end

  -- snacks.nvim (optional)
  local has_snacks = pcall(require, "snacks")
  if has_snacks then
    health.ok("snacks.nvim found (TUI fully functional)")
  else
    health.info("snacks.nvim not found — TUI will use vim.ui.input / vim.ui.select fallback")
  end

  -- State file
  local state = require("colorful-times.state")
  local path  = state.path()
  local dir   = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 1 or vim.fn.mkdir(dir, "p") == 1 then
    health.ok("State directory writable: " .. dir)
  else
    health.warn("State directory not writable: " .. dir .. " (TUI changes won't persist)")
  end

  -- Schedule validation
  local M_cfg  = require("colorful-times")
  local sched  = require("colorful-times.schedule")
  local bad    = 0
  for idx, entry in ipairs(M_cfg.config.schedule) do
    local ok, err = sched.validate_entry(entry)
    if not ok then
      health.warn(string.format("Schedule entry %d is invalid: %s", idx, err))
      bad = bad + 1
    end
  end
  if bad == 0 then
    health.ok(string.format("Schedule: %d entries, all valid", #M_cfg.config.schedule))
  end

  -- Current colorscheme
  local cs = vim.g.colors_name or "(none)"
  health.info("Current colorscheme: " .. cs)
end

return M
