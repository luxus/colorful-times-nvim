-- lua/colorful-times/tui.lua
-- Modernized TUI with fixed preselection

local M = {}
local api = vim.api
local ct = require("colorful-times")
local sched = require("colorful-times.schedule")

local VERSION = "2.1.0"
local MAX_COLORSCHEMES = 200

local BG_OPTIONS = { "system", "dark", "light" }
local BG_MAP = { system = 1, dark = 2, light = 3 }

-- ─── State ───────────────────────────────────────────────────────────────────
local _buf, _win, _cursor = nil, nil, 1
local NS = api.nvim_create_namespace("colorful_times_tui")

-- ─── Layout ───────────────────────────────────────────────────────────────────
local COLS = { 7, 7, 30, 8 }  -- START STOP COLORSCHEME BG
local HEADER_LINES = 4
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

-- ─── Debounced Save Timer ───────────────────────────────────────────────────
local _save_timer = nil
local DEBOUNCE_MS = 500  -- Delay saves by 500ms to batch rapid changes

-- ─── Formatting ───────────────────────────────────────────────────────────────
local function pad(str, width)
  str = tostring(str or "")
  return #str >= width and str:sub(1, width - 1) .. " " or str .. string.rep(" ", width - #str)
end

-- ─── Static Header Cache ─────────────────────────────────────────────────────
local _static_header = nil
local function get_static_header(enabled)
  local cache_key = enabled and "enabled" or "disabled"
  if not _static_header or _static_header.key ~= cache_key then
    _static_header = {
      key = cache_key,
      lines = {
        enabled and "  [●] ENABLED  " .. VERSION or "  [○] DISABLED " .. VERSION,
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
  table.insert(lines, "  [a]dd [e]dit [d]el [t]oggle [r]eload [?]help [q]uit")
  
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
      require("snacks").input({ prompt = prompt, default = default or "" }, handler)
    else
      vim.ui.input(opts, handler)
    end
  end
  ask()
end

---@param default? string
---@param cb fun(name: string|nil)
local function pick_colorscheme(default, cb)
  local original_cs, original_bg = vim.g.colors_name, vim.o.background
  local schemes = get_cached_schemes()
  
  local function revert()
    pcall(vim.cmd.colorscheme, original_cs)
    vim.o.background = original_bg
  end
  
  if has_snacks() then
    require("snacks").picker.pick({
      title = "Colorscheme",
      items = vim.iter(schemes):map(function(s) return { text = s } end):totable(),
      format = "text",
      -- FIX: Preselect the default colorscheme (return index)
      selected = default and (function()
        for i, s in ipairs(schemes) do
          if s == default then return i end
        end
      end)() or nil,
      on_change = function(_, item)
        if item then pcall(vim.cmd.colorscheme, item.text) end
      end,
      confirm = function(picker, item)
        picker:close()
        if item then cb(item.text) else revert(); cb(nil) end
      end,
      on_close = revert,
    })
  else
    -- Fallback: find index of default for preselection
    local default_idx = 1
    if default then
      for i, s in ipairs(schemes) do
        if s == default then default_idx = i; break end
      end
    end
    vim.ui.select(schemes, { prompt = "Colorscheme: ", default = default_idx }, function(choice)
      if choice then cb(choice) else cb(nil) end
    end)
  end
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
        vim.ui.select(BG_OPTIONS, {
          prompt = "Background: ",
          default = existing and BG_MAP[existing.background] or 1,
        }, function(bg)
          cb(bg and { start = start, stop = stop, colorscheme = cs, background = bg } or nil)
        end)
      end)
    end)
  end)
end

-- ─── Actions ─────────────────────────────────────────────────────────────────
local function save_and_reload()
  -- Always reload immediately for responsive UI
  require("colorful-times.core").reload()
  render()
  
  -- Debounce state saves to reduce disk I/O during rapid changes
  if not ct.config.persist then return end
  
  if _save_timer then
    _save_timer:stop()
    _save_timer:close()
  end
  
  _save_timer = vim.uv.new_timer()
  _save_timer:start(DEBOUNCE_MS, 0, function()
    _save_timer:close()
    _save_timer = nil
    require("colorful-times.state").save({
      enabled = ct.config.enabled,
      schedule = ct.config.schedule,
    })
  end)
end

local function action_add()
  -- FIX: Preselect current theme for new entries
  local current_cs = vim.g.colors_name or ct.config.default.colorscheme
  local current_bg = vim.o.background or ct.config.default.background
  
  prompt_time("Start time (HH:MM)", nil, function(start)
    if not start then return end
    prompt_time("Stop time (HH:MM)", nil, function(stop)
      if not stop then return end
      pick_colorscheme(current_cs, function(cs)
        if not cs then return end
        vim.ui.select(BG_OPTIONS, {
          prompt = "Background: ",
          default = BG_MAP[current_bg] or 1,
        }, function(bg)
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
    "  j/↓ move  k/↑ move  a add  e/Enter edit  d/x del  t toggle  r reload  q/Esc quit",
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
  map("t", action_toggle)
  map("r", action_reload)
  map("?", action_help)
  map("q", close)
  map("<Esc>", close)
  
  render()
end

return M
