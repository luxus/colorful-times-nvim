-- lua/colorful-times/tui.lua
-- Modernized TUI with fixed preselection

local M = {}
local api = vim.api
local ct = require("colorful-times")
local sched = require("colorful-times.schedule")

local VERSION = "2.2.0"
local MAX_COLORSCHEMES = 200

-- ─── State ───────────────────────────────────────────────────────────────────
local _buf, _win, _cursor = nil, nil, 1
local NS = api.nvim_create_namespace("colorful_times_tui")

-- ─── Layout ───────────────────────────────────────────────────────────────────
local COLS = { 7, 7, 30, 8 }  -- START STOP COLORSCHEME BG
local HEADER_LINES = 8
local SEP = string.rep("─", vim.iter(COLS):fold(9, function(a, b) return a + b end))

-- ─── Snacks Detection ───────────────────────────────────────────────────────
local _has_snacks = nil
local function has_snacks()
  if _has_snacks == nil then
    _has_snacks = pcall(require, "snacks")
  end
  return _has_snacks
end

-- ─── Colorscheme List Cache ──────────────────────────────────────────────────
local _cached_schemes = nil
local function get_cached_schemes()
  if not _cached_schemes then
    _cached_schemes = vim.iter(vim.fn.getcompletion("", "color"))
      :filter(function(s) return s ~= "" end)
      :take(MAX_COLORSCHEMES)
      :totable()
  end
  return _cached_schemes
end

-- ─── Formatting ───────────────────────────────────────────────────────────────
local function pad(str, width)
  str = tostring(str or "")
  return #str >= width and str:sub(1, width - 1) .. " " or str .. string.rep(" ", width - #str)
end

local function focus_tui()
  vim.schedule(function()
    if _win and api.nvim_win_is_valid(_win) then
      api.nvim_set_current_win(_win)
    end
  end)
end

local function focus_then(cb)
  return function(...)
    cb(...)
    focus_tui()
  end
end

---@param value? string
---@return string
local function display_theme(value)
  return value and value ~= "" and value or "(use fallback)"
end

---@param bg? string
---@return integer
local function background_index(bg)
  if bg == "light" then
    return 1
  end
  if bg == "dark" then
    return 2
  end
  return 3
end

---@param title string
---@param default? string
---@param cb fun(bg: string|nil)
local function pick_background(title, default, cb)
  vim.ui.select({ "light", "dark", "system" }, {
    prompt = title .. ": ",
    default = background_index(default),
  }, focus_then(cb))
end

-- ─── Static Header Cache ─────────────────────────────────────────────────────
local _static_header = nil
local function get_static_header(enabled)
  local cache_key = table.concat({
    enabled and "enabled" or "disabled",
    ct.config.default.colorscheme or "",
    ct.config.default.background or "",
    ct.config.default.themes.light or "",
    ct.config.default.themes.dark or "",
  }, "\n")
  if not _static_header or _static_header.key ~= cache_key then
    _static_header = {
      key = cache_key,
      lines = {
        enabled and "  [●] ENABLED  " .. VERSION or "  [○] DISABLED " .. VERSION,
        SEP,
        string.format("  DEFAULT  %-30s BG %-8s", pad(ct.config.default.colorscheme, 30), pad(ct.config.default.background, 8)),
        string.format("  LIGHT    %-30s", pad(display_theme(ct.config.default.themes.light), 30)),
        string.format("  DARK     %-30s", pad(display_theme(ct.config.default.themes.dark), 30)),
        SEP,
        string.format("  %s%s%s%s", pad("START", COLS[1]), pad("STOP", COLS[2]), pad("COLORSCHEME", COLS[3]), pad("BG", COLS[4])),
        SEP,
      }
    }
  end
  return _static_header.lines
end

-- ─── Rendering ───────────────────────────────────────────────────────────────
local function render()
  if not (_buf and api.nvim_buf_is_valid(_buf)) then return end
  
  vim.bo[_buf].modifiable = true
  api.nvim_buf_clear_namespace(_buf, NS, 0, -1)
  
  -- Start with cached static header
  local lines = { unpack(get_static_header(ct.config.enabled)) }
  
  local schedule = ct.config.schedule
  if #schedule == 0 then
    table.insert(lines, "  (no entries — press [a] to add)")
  else
    for _, entry in ipairs(schedule) do
      table.insert(lines, string.format("  %s%s%s%s",
        pad(entry.start, COLS[1]), pad(entry.stop, COLS[2]),
        pad(entry.colorscheme, COLS[3]), pad(entry.background or "—", COLS[4])))
    end
  end
  
  -- Footer (static, but keep inline for clarity)
  table.insert(lines, SEP)
  table.insert(lines, "  [a]dd [e]dit [d]el [c]olor [b]g [l]ight [n]ight [t]oggle [r]eload [?]help [q]uit")
  
  api.nvim_buf_set_lines(_buf, 0, -1, false, lines)
  vim.bo[_buf].modifiable = false
  
  -- Highlight selected row
  if #schedule > 0 then
    api.nvim_buf_add_highlight(_buf, NS, "Visual", HEADER_LINES + _cursor - 1, 0, -1)
  end
end

-- ─── Form Helpers ─────────────────────────────────────────────────────────────

---@param prompt string
---@param default? string
---@param cb fun(value: string|nil)
local function prompt_time(prompt, default, cb)
  local function ask()
    local opts = { prompt = prompt .. ": ", default = default or "" }
    local function handler(value)
      if not value then cb(nil); return end
      if sched.parse_time(value) then cb(value) else
        vim.notify("Invalid time (use HH:MM)", vim.log.levels.WARN)
        ask()
      end
    end
    
    if has_snacks() then
      require("snacks").input({ prompt = prompt, default = default or "" }, focus_then(handler))
    else
      vim.ui.input(opts, focus_then(handler))
    end
  end
  ask()
end

---@param default? string
---@param cb fun(name: string|nil)
local function pick_colorscheme(default, cb)
  local schemes = get_cached_schemes()

  local default_idx = 1
  if default then
    for i, s in ipairs(schemes) do
      if s == default then
        default_idx = i
        break
      end
    end
  end

  vim.ui.select(schemes, {
    prompt = "Colorscheme: ",
    default = default_idx,
  }, focus_then(function(choice)
    if choice then
      cb(choice)
    else
      cb(nil)
    end
  end))
end

---@param label string
---@param default? string
---@param cb fun(name: string|nil)
local function pick_optional_colorscheme(label, default, cb)
  local clear_label = "(use fallback)"
  local schemes = { clear_label }
  vim.list_extend(schemes, get_cached_schemes())

  local selected = 1
  if default then
    for i = 2, #schemes do
      if schemes[i] == default then
        selected = i
        break
      end
    end
  end

  vim.ui.select(schemes, {
    prompt = label .. ": ",
    default = selected,
  }, focus_then(function(choice)
    if not choice then
      cb(nil)
      return
    end
    cb(choice == clear_label and vim.NIL or choice)
  end))
end

---@param existing? table
---@param cb fun(entry: table|nil)
local function entry_form(existing, cb)
  prompt_time("Start time (HH:MM)", existing and existing.start, function(start)
    if not start then cb(nil); return end
    prompt_time("Stop time (HH:MM)", existing and existing.stop, function(stop)
      if not stop then cb(nil); return end
      pick_colorscheme(existing and existing.colorscheme, function(cs)
        if not cs then cb(nil); return end
        pick_background("Background", existing and existing.background, function(bg)
          cb(bg and { start = start, stop = stop, colorscheme = cs, background = bg } or nil)
        end)
      end)
    end)
  end)
end

-- ─── Actions ─────────────────────────────────────────────────────────────────
local function save_and_reload()
  local core = require("colorful-times.core")
  core.save_state()
  core.reload()
  render()
  focus_tui()
end

local function action_add()
  local current_cs = vim.g.colors_name or ct.config.default.colorscheme
  local current_bg = vim.o.background or ct.config.default.background
  
  prompt_time("Start time (HH:MM)", nil, function(start)
    if not start then return end
    prompt_time("Stop time (HH:MM)", nil, function(stop)
      if not stop then return end
      pick_colorscheme(current_cs, function(cs)
        if not cs then return end
        pick_background("Background", current_bg, function(bg)
          if bg then
            table.insert(ct.config.schedule, { start = start, stop = stop, colorscheme = cs, background = bg })
            _cursor = #ct.config.schedule
            save_and_reload()
          end
        end)
      end)
    end)
  end)
end

local function action_edit()
  if _cursor < 1 or _cursor > #ct.config.schedule then return end
  entry_form(ct.config.schedule[_cursor], function(entry)
    if entry then
      ct.config.schedule[_cursor] = entry
      save_and_reload()
    end
  end)
end

local function action_delete()
  local entry = ct.config.schedule[_cursor]
  if not entry then return end
  vim.ui.select({ "Yes", "No" }, {
    prompt = string.format("Delete %s–%s %s? ", entry.start, entry.stop, entry.colorscheme),
  }, function(choice)
    if choice == "Yes" then
      table.remove(ct.config.schedule, _cursor)
      _cursor = math.max(1, math.min(_cursor, #ct.config.schedule))
      save_and_reload()
    end
  end)
end

local function action_default_colorscheme()
  pick_colorscheme(ct.config.default.colorscheme, function(cs)
    if not cs then
      return
    end
    ct.config.default.colorscheme = cs
    save_and_reload()
  end)
end

local function action_default_background()
  pick_background("Default background", ct.config.default.background, function(bg)
    if not bg then
      return
    end
    ct.config.default.background = bg
    save_and_reload()
  end)
end

---@param kind "light"|"dark"
local function action_theme_override(kind)
  pick_optional_colorscheme(kind == "light" and "Light override" or "Dark override", ct.config.default.themes[kind], function(cs)
    if cs == nil then
      return
    end
    ct.config.default.themes[kind] = cs == vim.NIL and nil or cs
    save_and_reload()
  end)
end

local function action_toggle()
  require("colorful-times.core").toggle()
  render()
end

local function action_reload()
  require("colorful-times.core").reload()
  render()
  vim.notify("colorful-times: reloaded", vim.log.levels.INFO)
end

local function action_help()
  vim.notify(table.concat({
    "colorful-times keys:",
    "  j/↓ move  k/↑ move  a add  e/Enter edit  d/x del",
    "  c default colorscheme  b default background  l light theme  n night theme",
    "  t toggle  r reload  q/Esc quit",
  }, "\n"), vim.log.levels.INFO)
end

local function cursor_move(delta)
  _cursor = math.max(1, math.min(math.max(1, #ct.config.schedule), _cursor + delta))
  render()
end

local function close()
  if _win and api.nvim_win_is_valid(_win) then
    api.nvim_win_close(_win, true)
  end
  _win, _buf = nil, nil
end

-- ─── Public API ─────────────────────────────────────────────────────────────
function M.open()
  if _win and api.nvim_win_is_valid(_win) then
    api.nvim_set_current_win(_win)
    return
  end
  
  _buf = api.nvim_create_buf(false, true)
  vim.bo[_buf].buftype, vim.bo[_buf].bufhidden, vim.bo[_buf].filetype, vim.bo[_buf].modifiable =
    "nofile", "wipe", "colorful-times", false
  
  local ui = api.nvim_list_uis()[1]
  local width, height = math.floor(ui.width * 0.6), math.min(math.max(10, #ct.config.schedule + 6), math.floor(ui.height * 0.8))
  
  _win = api.nvim_open_win(_buf, true, {
    relative = "editor", width = width, height = height,
    row = math.floor((ui.height - height) / 2), col = math.floor((ui.width - width) / 2),
    style = "minimal", border = "rounded",
    title = " Colorful Times ", title_pos = "center",
  })
  
  _cursor = math.max(1, math.min(_cursor, math.max(1, #ct.config.schedule)))
  
  -- Keymaps
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = _buf, nowait = true, silent = true })
  end
  
  map("j", function() cursor_move(1) end)
  map("<Down>", function() cursor_move(1) end)
  map("k", function() cursor_move(-1) end)
  map("<Up>", function() cursor_move(-1) end)
  map("a", action_add)
  map("e", action_edit)
  map("<CR>", action_edit)
  map("d", action_delete)
  map("x", action_delete)
  map("c", action_default_colorscheme)
  map("b", action_default_background)
  map("l", function() action_theme_override("light") end)
  map("n", function() action_theme_override("dark") end)
  map("t", action_toggle)
  map("r", action_reload)
  map("?", action_help)
  map("q", close)
  map("<Esc>", close)
  
  render()
end

return M
