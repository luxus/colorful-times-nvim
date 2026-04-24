-- lua/colorful-times/tui/highlights.lua
-- TUI-local highlight namespace and groups.

local M = {}

local ns = vim.api.nvim_create_namespace("colorful_times_tui")

local function hl(group, spec)
  vim.api.nvim_set_hl(ns, group, spec)
end

function M.setup(win)
  hl("ColorfulTimesTitle", { fg = "#c084fc", bold = true })
  hl("ColorfulTimesDim", { fg = "#6b7280" })
  hl("ColorfulTimesMuted", { fg = "#94a3b8" })
  hl("ColorfulTimesEnabled", { fg = "#22c55e", bold = true })
  hl("ColorfulTimesDisabled", { fg = "#64748b", bold = true })
  hl("ColorfulTimesPinned", { fg = "#f0abfc", bold = true })
  hl("ColorfulTimesAccent", { fg = "#38bdf8", bold = true })
  hl("ColorfulTimesWarn", { fg = "#fbbf24", bold = true })
  hl("ColorfulTimesDanger", { fg = "#ffffff", bg = "#dc2626", bold = true, reverse = true })
  hl("ColorfulTimesSelected", { fg = "#ffffff", bg = "#4c1d95", bold = true })
  hl("ColorfulTimesActive", { fg = "#10b981", bold = true })
  hl("ColorfulTimesField", { fg = "#e879f9", bold = true })
  hl("ColorfulTimesFooter", { fg = "#93c5fd" })
  hl("ColorfulTimesFrame", { fg = "#94a3b8" })
  hl("ColorfulTimesFrameFocus", { fg = "#c084fc", bold = true })
  hl("ColorfulTimesTimeline", { fg = "#38bdf8" })

  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_hl_ns(win, ns)
  end
end

function M.ns()
  return ns
end

return M
