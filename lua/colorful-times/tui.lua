-- lua/colorful-times/tui.lua
-- Table Manager TUI. Loaded only on demand (:ColorfulTimes / M.open()).
-- Uses snacks.nvim when available; falls back to vim.ui.* otherwise.

local M      = {}
local api    = vim.api
local ct     = require("colorful-times")
local sched  = require("colorful-times.schedule")

local VERSION = "2.0.0"
local MAX_COLORSCHEMES = 200

-- ─── Snacks detection ────────────────────────────────────────────────────────

---@return boolean has_snacks Whether snacks.nvim is available
local function has_snacks()
  return pcall(require, "snacks")
end

-- ─── Window state ────────────────────────────────────────────────────────────

local _state = {
  buf     = nil,  -- buffer handle
  win     = nil,  -- window handle
  cursor  = 1,    -- 1-indexed selected row (into schedule)
}

local NS = api.nvim_create_namespace("colorful_times_tui")

-- ─── Rendering ───────────────────────────────────────────────────────────────

local COL_WIDTHS = { 7, 7, 30, 8 }  -- START STOP COLORSCHEME BG
local HEADER_SEP = string.rep("─", COL_WIDTHS[1] + COL_WIDTHS[2] + COL_WIDTHS[3] + COL_WIDTHS[4] + 9)

---@param str string String to pad
---@param width number Target width
---@return string padded The padded string
local function pad(str, width)
  str = tostring(str or "")
  if #str >= width then return str:sub(1, width - 1) .. " " end
  return str .. string.rep(" ", width - #str)
end

---Render the TUI content in the buffer
---@return nil
local function render()
  if not (_state.buf and api.nvim_buf_is_valid(_state.buf)) then return end

  vim.bo[_state.buf].modifiable = true
  api.nvim_buf_clear_namespace(_state.buf, NS, 0, -1)

  local lines = {}
  -- Status bar
  local status = ct.config.enabled
    and "  [●] ENABLED  " .. VERSION
    or  "  [○] DISABLED " .. VERSION
  table.insert(lines, status)
  table.insert(lines, HEADER_SEP)

  -- Header row
  table.insert(lines, string.format(
    "  %s%s%s%s",
    pad("START", COL_WIDTHS[1]),
    pad("STOP",  COL_WIDTHS[2]),
    pad("COLORSCHEME", COL_WIDTHS[3]),
    pad("BG", COL_WIDTHS[4])
  ))
  table.insert(lines, HEADER_SEP)

  -- Schedule rows
  local schedule = ct.config.schedule
  if #schedule == 0 then
    table.insert(lines, "  (no entries — press [a] to add)")
  else
    for _, entry in ipairs(schedule) do
      table.insert(lines, string.format(
        "  %s%s%s%s",
        pad(entry.start,        COL_WIDTHS[1]),
        pad(entry.stop,         COL_WIDTHS[2]),
        pad(entry.colorscheme,  COL_WIDTHS[3]),
        pad(entry.background or "—", COL_WIDTHS[4])
      ))
    end
  end

  table.insert(lines, HEADER_SEP)
  table.insert(lines, "  [a]dd [e]dit [d]el [t]oggle [r]eload [?]help [q]uit")

  api.nvim_buf_set_lines(_state.buf, 0, -1, false, lines)
  vim.bo[_state.buf].modifiable = false

  -- Highlight selected row (rows start at line 5 = index 4, 0-based)
  local HEADER_LINES = 4
  local selected_line = HEADER_LINES + _state.cursor - 1
  if #schedule > 0 then
    api.nvim_buf_add_highlight(_state.buf, NS, "Visual", selected_line, 0, -1)
  end
end

-- ─── Form helpers ─────────────────────────────────────────────────────────────

-- Prompt for a validated HH:MM time string.
-- Calls cb(time_str) on success, cb(nil) on cancel.
---@param prompt_text string The prompt text to display
---@param default string|nil Default value
---@param cb fun(time_str: string|nil) Callback with time string or nil on cancel
local function prompt_time(prompt_text, default, cb)
  local function ask()
    if has_snacks() then
      require("snacks").input({
        prompt  = prompt_text,
        default = default or "",
      }, function(value)
        if not value then cb(nil); return end
        if sched.parse_time(value) then
          cb(value)
        else
          vim.notify("colorful-times: invalid time: '" .. value .. "' (use HH:MM)", vim.log.levels.WARN)
          ask()  -- re-prompt
        end
      end)
    else
      vim.ui.input({ prompt = prompt_text .. ": ", default = default or "" }, function(value)
        if not value then cb(nil); return end
        if sched.parse_time(value) then
          cb(value)
        else
          vim.notify("colorful-times: invalid time: '" .. value .. "' (use HH:MM)", vim.log.levels.WARN)
          ask()
        end
      end)
    end
  end
  ask()
end

-- Fuzzy colorscheme picker with live preview.
-- Calls cb(name) on confirm, cb(nil) on cancel.
---@param _default string|nil Default colorscheme name (unused but kept for API consistency)
---@param cb fun(name: string|nil) Callback with selected colorscheme or nil on cancel
local function pick_colorscheme(_default, cb)
  local original_cs = vim.g.colors_name
  local original_bg = vim.o.background

  local schemes = vim.fn.getcompletion("", "color")

  local function revert()
    pcall(vim.cmd.colorscheme, original_cs)
    vim.o.background = original_bg
  end

  if has_snacks() then
    require("snacks").picker.pick({
      title  = "Colorscheme",
      items  = vim.tbl_map(function(s) return { text = s } end, schemes),
      format = "text",
      on_change = function(_, item)
        if item then
          pcall(vim.cmd.colorscheme, item.text)
        end
      end,
      confirm = function(picker, item)
        picker:close()
        if item then
          cb(item.text)
        else
          revert()
          cb(nil)
        end
      end,
    })
  else
    -- Fallback: vim.ui.select (no live preview)
    -- Cap at MAX_COLORSCHEMES to avoid unusable overflow
    local display = #schemes > MAX_COLORSCHEMES and vim.list_slice(schemes, 1, MAX_COLORSCHEMES) or schemes
    vim.ui.select(display, {
      prompt = "Colorscheme (showing first " .. MAX_COLORSCHEMES .. " of " .. #schemes .. "): ",
    }, function(choice)
      if choice then cb(choice) else cb(nil) end
    end)
  end
end

-- Sequential form: collect all fields for an entry, call cb(entry) or cb(nil) on cancel.
---@param existing table|nil Existing entry to edit, or nil for new entry
---@param cb fun(entry: table|nil) Callback with entry table or nil on cancel
local function entry_form(existing, cb)
  prompt_time("Start time (HH:MM)", existing and existing.start, function(start)
    if not start then cb(nil); return end
    prompt_time("Stop time (HH:MM)", existing and existing.stop, function(stop)
      if not stop then cb(nil); return end
      pick_colorscheme(existing and existing.colorscheme, function(cs)
        if not cs then cb(nil); return end
        vim.ui.select(
          { "system", "dark", "light" },
          { prompt = "Background: " },
          function(bg)
            if not bg then cb(nil); return end
            cb({ start = start, stop = stop, colorscheme = cs, background = bg })
          end
        )
      end)
    end)
  end)
end

-- ─── Actions ─────────────────────────────────────────────────────────────────

---Save state and reload the configuration
---@return nil
local function save_and_reload()
  local core = require("colorful-times.core")
  if ct.config.persist then
    require("colorful-times.state").save({
      enabled  = ct.config.enabled,
      schedule = ct.config.schedule,
    })
  end
  core.reload()
  render()
end

---Add a new schedule entry
---@return nil
local function action_add()
  entry_form(nil, function(entry)
    if not entry then return end
    table.insert(ct.config.schedule, entry)
    _state.cursor = #ct.config.schedule
    save_and_reload()
  end)
end

---Edit the currently selected schedule entry
---@return nil
local function action_edit()
  local idx = _state.cursor
  if idx < 1 or idx > #ct.config.schedule then return end
  local existing = ct.config.schedule[idx]
  entry_form(existing, function(entry)
    if not entry then return end
    ct.config.schedule[idx] = entry
    save_and_reload()
  end)
end

---Delete the currently selected schedule entry
---@return nil
local function action_delete()
  local idx = _state.cursor
  if idx < 1 or idx > #ct.config.schedule then return end
  local entry = ct.config.schedule[idx]
  vim.ui.select({ "Yes", "No" }, {
    prompt = string.format("Delete %s–%s %s? ", entry.start, entry.stop, entry.colorscheme),
  }, function(choice)
    if choice ~= "Yes" then return end
    table.remove(ct.config.schedule, idx)
    if _state.cursor > #ct.config.schedule and _state.cursor > 1 then
      _state.cursor = _state.cursor - 1
    end
    save_and_reload()
  end)
end

---Toggle the plugin enabled/disabled state
---@return nil
local function action_toggle()
  require("colorful-times.core").toggle()
  render()
end

---Reload the configuration and refresh the TUI
---@return nil
local function action_reload()
  require("colorful-times.core").reload()
  render()
  vim.notify("colorful-times: config reloaded", vim.log.levels.INFO)
end

---Show help information
---@return nil
local function action_help()
  local help = {
    "colorful-times keymaps:",
    "  j / ↓      move down",
    "  k / ↑      move up",
    "  a          add entry",
    "  e / Enter  edit entry",
    "  d / x      delete entry",
    "  t          toggle enabled",
    "  r          reload config",
    "  q / Esc    close",
  }
  vim.notify(table.concat(help, "\n"), vim.log.levels.INFO)
end

---@param delta number Direction to move (-1 for up, 1 for down)
---@return nil
local function cursor_move(delta)
  local n = math.max(1, #ct.config.schedule)
  _state.cursor = math.max(1, math.min(n, _state.cursor + delta))
  render()
end

-- ─── Open / Close ─────────────────────────────────────────────────────────────

---Close the TUI window
---@return nil
local function close()
  if _state.win and api.nvim_win_is_valid(_state.win) then
    api.nvim_win_close(_state.win, true)
  end
  _state.win = nil
  _state.buf = nil
end

---Open the Colorful Times TUI window
---Interactive schedule manager with keybindings for add/edit/delete/toggle
---@return nil
function M.open()
  if _state.win and api.nvim_win_is_valid(_state.win) then
    api.nvim_set_current_win(_state.win)
    return
  end

  -- Create buffer
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].bufhidden  = "wipe"
  vim.bo[buf].filetype   = "colorful-times"
  vim.bo[buf].modifiable = false

  -- Compute window size
  local ui       = api.nvim_list_uis()[1]
  local width    = math.floor(ui.width * 0.6)
  local n_rows   = math.max(10, #ct.config.schedule + 6)  -- header + footer rows
  local height   = math.min(n_rows, math.floor(ui.height * 0.8))
  local row      = math.floor((ui.height - height) / 2)
  local col      = math.floor((ui.width  - width)  / 2)

  local win = api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    style     = "minimal",
    border    = "rounded",
    title     = " Colorful Times ",
    title_pos = "center",
  })

  _state.buf    = buf
  _state.win    = win
  _state.cursor = math.max(1, math.min(_state.cursor, math.max(1, #ct.config.schedule)))

  -- Keymaps (buffer-local, normal mode)
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
  end

  map("j",      function() cursor_move(1)  end)
  map("<Down>", function() cursor_move(1)  end)
  map("k",      function() cursor_move(-1) end)
  map("<Up>",   function() cursor_move(-1) end)
  map("a",      action_add)
  map("e",      action_edit)
  map("<CR>",   action_edit)
  map("d",      action_delete)
  map("x",      action_delete)
  map("t",      action_toggle)
  map("r",      action_reload)
  map("?",      action_help)
  map("q",      close)
  map("<Esc>",  close)

  render()
end

return M
