-- lua/colorful-times/tui/highlights.lua
-- TUI-local highlight namespace and groups.

local M = {}

local ns = vim.api.nvim_create_namespace("colorful_times_tui")

local DEFAULT_SPECS = {
  ColorfulTimesTitle = { fg = "#c084fc", bold = true },
  ColorfulTimesDim = { fg = "#475569" },
  ColorfulTimesMuted = { fg = "#64748b" },
  ColorfulTimesEnabled = { fg = "#22c55e", bold = true },
  ColorfulTimesDisabled = { fg = "#64748b", bold = true },
  ColorfulTimesPinned = { fg = "#a855f7", bold = true },
  ColorfulTimesAccent = { fg = "#0ea5e9", bold = true },
  ColorfulTimesWarn = { fg = "#f59e0b", bold = true },
  ColorfulTimesDanger = { fg = "#ffffff", bg = "#dc2626", bold = true, reverse = true },
  ColorfulTimesSelected = { fg = "#ffffff", bg = "#4c1d95", bold = true },
  ColorfulTimesActive = { fg = "#10b981", bold = true },
  ColorfulTimesField = { fg = "#f5d0fe", bg = "#4c1d95", bold = true },
  ColorfulTimesFooter = { fg = "#3b82f6" },
  ColorfulTimesFrame = { fg = "#64748b" },
  ColorfulTimesFrameFocus = { fg = "#c084fc", bold = true },
  ColorfulTimesTimeline = { fg = "#0ea5e9" },
}

local SEMANTIC_MAP = {
  ColorfulTimesTitle = "Title",
  ColorfulTimesDim = "NonText",
  ColorfulTimesMuted = "Comment",
  ColorfulTimesEnabled = "DiagnosticOk",
  ColorfulTimesDisabled = "Comment",
  ColorfulTimesPinned = "Identifier",
  ColorfulTimesAccent = "Keyword",
  ColorfulTimesWarn = "WarningMsg",
  ColorfulTimesDanger = "ErrorMsg",
  ColorfulTimesSelected = "Visual",
  ColorfulTimesActive = "String",
  ColorfulTimesField = "Search",
  ColorfulTimesFooter = "LineNr",
  ColorfulTimesFrame = "FloatBorder",
  ColorfulTimesFrameFocus = "FloatTitle",
  ColorfulTimesTimeline = "Number",
}

local function hl(group, spec)
  vim.api.nvim_set_hl(ns, group, spec)
end

local function get_semantic_hl(group_name)
  local ok, hl_def = pcall(vim.api.nvim_get_hl, 0, { name = group_name, link = false })
  if ok and hl_def and (hl_def.fg or hl_def.bg or hl_def.sp or hl_def.bold or hl_def.italic or hl_def.reverse or hl_def.underline) then
    return hl_def
  end
  return nil
end

---@param win integer
---@param mode "default" | "theme"
function M.setup(win, mode)
  mode = mode or "default"

  for group, default_spec in pairs(DEFAULT_SPECS) do
    if mode == "theme" then
      local semantic_group = SEMANTIC_MAP[group]
      local semantic_hl = semantic_group and get_semantic_hl(semantic_group)
      if semantic_hl then
        hl(group, semantic_hl)
      else
        hl(group, default_spec)
      end
    else
      hl(group, default_spec)
    end
  end

  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_hl_ns(win, ns)
  end
end

function M.ns()
  return ns
end

return M
