-- lua/colorful-times/tui.lua
-- Interactive TUI for schedule and default theme management

local M = {}
local api = vim.api
local ct = require("colorful-times")
local sched = require("colorful-times.schedule")

local VERSION = "2.2.0"
local MAX_COLORSCHEMES = 200
local MIN_THEME_COL = 18
local MAX_THEME_COL = 34
local MIN_WINDOW_WIDTH = 54

local _buf, _win, _cursor = nil, nil, 1
local _draft = nil
local NS = api.nvim_create_namespace("colorful_times_tui")

local _has_snacks = nil
local _cached_schemes = nil
local _static_header = nil

local function has_snacks()
  if _has_snacks == nil then
    _has_snacks = pcall(require, "snacks")
  end
  return _has_snacks
end

local function get_cached_schemes()
  if not _cached_schemes then
    _cached_schemes = vim.iter(vim.fn.getcompletion("", "color"))
      :filter(function(s) return s ~= "" end)
      :take(MAX_COLORSCHEMES)
      :totable()
  end
  return _cached_schemes
end

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

local function focus_tui_deferred()
  vim.defer_fn(focus_tui, 20)
end

---@param value? string
---@return string
local function display_theme(value)
  return value and value ~= "" and value or "(fallback)"
end

---@param value? string
---@return string
local function display_cell(value)
  return value and value ~= "" and value or "—"
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

local function current_theme_snapshot()
  return vim.g.colors_name, vim.o.background
end

---@param colorscheme? string
---@param background? string
local function restore_theme(colorscheme, background)
  if background and background ~= "" then
    vim.o.background = background
  end
  if colorscheme and colorscheme ~= "" then
    pcall(vim.cmd.colorscheme, colorscheme)
  end
end

---@param title string
---@param items string[]
---@param default_idx integer
---@param cb fun(choice: string|nil)
local function pick_list(title, items, default_idx, cb)
  if has_snacks() then
    local picker = require("snacks").picker
    picker.pick({
      title = title,
      items = vim.iter(items):map(function(item)
        return { text = item }
      end):totable(),
      format = "text",
      selected = default_idx,
      confirm = function(instance, item)
        instance:close()
        cb(item and item.text or nil)
      end,
      on_close = function()
        focus_tui_deferred()
      end,
    })
    return
  end

  vim.ui.select(items, {
    prompt = title .. ": ",
    default = default_idx,
  }, function(choice)
    cb(choice)
    focus_tui_deferred()
  end)
end

---@param prompt string
---@param default? string
---@param cb fun(value: string|nil)
local function prompt_time(prompt, default, cb)
  local function ask()
    local opts = { prompt = prompt .. ": ", default = default or "" }
    local function handler(value)
      if not value then
        cb(nil)
        return
      end
      if sched.parse_time(value) then
        cb(value)
        return
      end

      vim.notify("Invalid time (use HH:MM)", vim.log.levels.WARN)
      ask()
    end

    if has_snacks() then
      require("snacks").input({
        prompt = prompt,
        default = default or "",
      }, handler)
      return
    end

    vim.ui.input(opts, function(value)
      handler(value)
      if not value then
        focus_tui_deferred()
      end
    end)
  end

  ask()
end

local function widest_theme_value()
  local widest = math.max(#display_theme(ct.config.default.colorscheme), 11)
  local function consider(value)
    widest = math.max(widest, #display_theme(value))
  end

  consider(ct.config.default.themes.light)
  consider(ct.config.default.themes.dark)

  for _, entry in ipairs(ct.config.schedule) do
    consider(entry.colorscheme)
  end

  if _draft then
    consider(_draft.colorscheme)
  end

  return math.min(MAX_THEME_COL, math.max(MIN_THEME_COL, widest + 1))
end

local function current_columns()
  return { 7, 7, widest_theme_value(), 8 }
end

local function table_width(cols)
  return vim.iter(cols):fold(2, function(sum, width)
    return sum + width
  end)
end

local function separator(cols)
  return string.rep("─", table_width(cols))
end

---@param cols integer[]
---@param prefix string
---@param start string
---@param stop string
---@param colorscheme string
---@param background string
---@return string
local function format_entry_row(cols, prefix, start, stop, colorscheme, background)
  return string.format("%s%s%s%s%s",
    prefix,
    pad(display_cell(start), cols[1]),
    pad(display_cell(stop), cols[2]),
    pad(display_theme(colorscheme), cols[3]),
    pad(display_cell(background), cols[4]))
end

local function header_cache_key(cols, enabled)
  return table.concat({
    enabled and "enabled" or "disabled",
    tostring(cols[3]),
    ct.config.default.colorscheme or "",
    ct.config.default.background or "",
    ct.config.default.themes.light or "",
    ct.config.default.themes.dark or "",
  }, "\n")
end

local function get_static_header(cols, enabled)
  local cache_key = header_cache_key(cols, enabled)
  local sep = separator(cols)
  if not _static_header or _static_header.key ~= cache_key then
    _static_header = {
      key = cache_key,
      lines = {
        enabled and "  [●] ENABLED  " .. VERSION or "  [○] DISABLED " .. VERSION,
        sep,
        format_entry_row(cols, "  DEFAULT ", "—", "—", ct.config.default.colorscheme, ct.config.default.background),
        format_entry_row(cols, "  LIGHT   ", "—", "—", ct.config.default.themes.light, "—"),
        format_entry_row(cols, "  DARK    ", "—", "—", ct.config.default.themes.dark, "—"),
        "  ORDER   schedule > default bg > override",
      },
    }
  end
  return _static_header.lines
end

local function footer_lines()
  return {
    "  [a] add  [e/<CR>] edit  [d/x] delete  [c] default  [b] bg",
    "  [l] light  [n] dark  [t] toggle  [r] reload  [?] help  [q] quit",
  }
end

local function draft_lines(cols)
  if not _draft then
    return {}
  end

  local title = _draft.mode == "edit" and "  EDIT    " or "  NEW     "
  local next_step = _draft.next_step and ("  NEXT    " .. _draft.next_step) or nil
  local lines = {
    format_entry_row(cols, title, _draft.start, _draft.stop, _draft.colorscheme, _draft.background),
  }
  if next_step then
    table.insert(lines, next_step)
  end
  return lines
end

local function render()
  if not (_buf and api.nvim_buf_is_valid(_buf)) then
    return
  end

  local cols = current_columns()
  local sep = separator(cols)
  local header = { unpack(get_static_header(cols, ct.config.enabled)) }
  vim.list_extend(header, draft_lines(cols))
  table.insert(header, sep)
  table.insert(header, format_entry_row(cols, "  ", "START", "STOP", "COLORSCHEME", "BG"))
  table.insert(header, sep)

  vim.bo[_buf].modifiable = true
  api.nvim_buf_clear_namespace(_buf, NS, 0, -1)

  local lines = { unpack(header) }
  local schedule = ct.config.schedule
  if #schedule == 0 then
    table.insert(lines, "  (no entries - press [a] to add)")
  else
    for _, entry in ipairs(schedule) do
      table.insert(lines, format_entry_row(cols, "  ", entry.start, entry.stop, entry.colorscheme, entry.background))
    end
  end

  table.insert(lines, sep)
  vim.list_extend(lines, footer_lines())

  api.nvim_buf_set_lines(_buf, 0, -1, false, lines)
  vim.bo[_buf].modifiable = false

  if #schedule > 0 then
    api.nvim_buf_add_highlight(_buf, NS, "Visual", #header + _cursor - 1, 0, -1)
  end
end

local function clear_draft()
  _draft = nil
  render()
end

---@param mode "add"|"edit"
---@param existing? ColorfulTimes.ScheduleEntry
---@param next_step? string
local function set_draft(mode, existing, next_step)
  _draft = {
    mode = mode,
    start = existing and existing.start or nil,
    stop = existing and existing.stop or nil,
    colorscheme = existing and existing.colorscheme or nil,
    background = existing and existing.background or nil,
    next_step = next_step,
  }
  render()
end

---@param patch table
local function update_draft(patch)
  if not _draft then
    return
  end
  _draft = vim.tbl_extend("force", _draft, patch)
  render()
end

local function save_and_reload()
  local core = require("colorful-times.core")
  core.save_state()
  core.reload()
  clear_draft()
  focus_tui_deferred()
end

---@param title string
---@param default? string
---@param cb fun(bg: string|nil)
local function pick_background(title, default, cb)
  local options = { "light", "dark", "system" }
  pick_list(title, options, background_index(default), cb)
end

---@param default? string
---@param title? string
---@param cb fun(name: string|nil)
local function pick_colorscheme(default, title, cb)
  local schemes = get_cached_schemes()
  local default_idx = 1
  if default then
    for i, name in ipairs(schemes) do
      if name == default then
        default_idx = i
        break
      end
    end
  end

  local original_cs, original_bg = current_theme_snapshot()

  if has_snacks() then
    require("snacks").picker.pick({
      title = title or "Colorscheme",
      items = vim.iter(schemes):map(function(name)
        return { text = name }
      end):totable(),
      format = "text",
      selected = default_idx,
      on_change = function(_, item)
        if item then
          pcall(vim.cmd.colorscheme, item.text)
        end
      end,
      confirm = function(instance, item)
        instance:close()
        cb(item and item.text or nil)
      end,
      on_close = function()
        restore_theme(original_cs, original_bg)
        focus_tui_deferred()
      end,
    })
    return
  end

  vim.ui.select(schemes, {
    prompt = (title or "Colorscheme") .. ": ",
    default = default_idx,
  }, function(choice)
    cb(choice)
    focus_tui_deferred()
  end)
end

---@param label string
---@param default? string
---@param cb fun(name: string|nil)
local function pick_optional_colorscheme(label, default, cb)
  local clear_label = "(fallback)"
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

  local original_cs, original_bg = current_theme_snapshot()

  if has_snacks() then
    require("snacks").picker.pick({
      title = label,
      items = vim.iter(schemes):map(function(name)
        return {
          text = name,
          previewable = name ~= clear_label,
        }
      end):totable(),
      format = "text",
      selected = selected,
      on_change = function(_, item)
        if not item then
          return
        end
        if item.text == clear_label then
          restore_theme(original_cs, original_bg)
          return
        end
        pcall(vim.cmd.colorscheme, item.text)
      end,
      confirm = function(instance, item)
        instance:close()
        if not item then
          cb(nil)
          return
        end
        cb(item.text == clear_label and vim.NIL or item.text)
      end,
      on_close = function()
        restore_theme(original_cs, original_bg)
        focus_tui_deferred()
      end,
    })
    return
  end

  vim.ui.select(schemes, {
    prompt = label .. ": ",
    default = selected,
  }, function(choice)
    if not choice then
      cb(nil)
    else
      cb(choice == clear_label and vim.NIL or choice)
    end
    focus_tui_deferred()
  end)
end

---@param mode "add"|"edit"
---@param initial? ColorfulTimes.ScheduleEntry
---@param cb fun(entry: ColorfulTimes.ScheduleEntry|nil)
local function entry_form(mode, initial, cb)
  set_draft(mode, initial, "start time")

  prompt_time("Start time (HH:MM)", initial and initial.start, function(start)
    if not start then
      clear_draft()
      focus_tui_deferred()
      cb(nil)
      return
    end

    update_draft({
      start = start,
      next_step = string.format("stop time for %s - %s", start, display_cell(_draft and _draft.stop)),
    })

    prompt_time(string.format("Stop time (HH:MM) [%s - ?]", start), initial and initial.stop, function(stop)
      if not stop then
        clear_draft()
        focus_tui_deferred()
        cb(nil)
        return
      end

      update_draft({
        stop = stop,
        next_step = string.format("colorscheme for %s - %s", start, stop),
      })

      pick_colorscheme(initial and initial.colorscheme,
        string.format("Colorscheme (%s - %s)", start, stop), function(colorscheme)
          if not colorscheme then
            clear_draft()
            focus_tui_deferred()
            cb(nil)
            return
          end

          update_draft({
            colorscheme = colorscheme,
            next_step = string.format("background for %s - %s", start, stop),
          })

          pick_background(string.format("Background (%s - %s)", start, stop),
            initial and initial.background, function(background)
              if not background then
                clear_draft()
                focus_tui_deferred()
                cb(nil)
                return
              end

              update_draft({
                background = background,
                next_step = nil,
              })

              cb({
                start = start,
                stop = stop,
                colorscheme = colorscheme,
                background = background,
              })
            end)
        end)
    end)
  end)
end

local function action_add()
  local current_cs = vim.g.colors_name or ct.config.default.colorscheme
  local current_bg = vim.o.background or ct.config.default.background
  entry_form("add", {
    start = nil,
    stop = nil,
    colorscheme = current_cs,
    background = current_bg,
  }, function(entry)
    if not entry then
      return
    end
    table.insert(ct.config.schedule, entry)
    _cursor = #ct.config.schedule
    save_and_reload()
  end)
end

local function action_edit()
  if _cursor < 1 or _cursor > #ct.config.schedule then
    return
  end
  entry_form("edit", ct.config.schedule[_cursor], function(entry)
    if not entry then
      return
    end
    ct.config.schedule[_cursor] = entry
    save_and_reload()
  end)
end

local function action_delete()
  local entry = ct.config.schedule[_cursor]
  if not entry then
    return
  end
  vim.ui.select({ "Yes", "No" }, {
    prompt = string.format("Delete %s-%s %s? ", entry.start, entry.stop, entry.colorscheme),
  }, function(choice)
    if choice == "Yes" then
      table.remove(ct.config.schedule, _cursor)
      _cursor = math.max(1, math.min(_cursor, #ct.config.schedule))
      save_and_reload()
      return
    end
    focus_tui_deferred()
  end)
end

local function action_default_colorscheme()
  pick_colorscheme(ct.config.default.colorscheme, "Default colorscheme", function(colorscheme)
    if not colorscheme then
      focus_tui_deferred()
      return
    end
    ct.config.default.colorscheme = colorscheme
    save_and_reload()
  end)
end

local function action_default_background()
  pick_background("Default background", ct.config.default.background, function(background)
    if not background then
      focus_tui_deferred()
      return
    end
    ct.config.default.background = background
    save_and_reload()
  end)
end

---@param kind "light"|"dark"
local function action_theme_override(kind)
  local label = kind == "light" and "Light override" or "Dark override"
  pick_optional_colorscheme(label, ct.config.default.themes[kind], function(colorscheme)
    if colorscheme == nil then
      focus_tui_deferred()
      return
    end
    ct.config.default.themes[kind] = colorscheme == vim.NIL and nil or colorscheme
    save_and_reload()
  end)
end

local function action_toggle()
  require("colorful-times.core").toggle()
  render()
  focus_tui_deferred()
end

local function action_reload()
  require("colorful-times.core").reload()
  render()
  focus_tui_deferred()
  vim.notify("colorful-times: reloaded", vim.log.levels.INFO)
end

local function action_help()
  vim.notify(table.concat({
    "colorful-times keys:",
    "  j/↓ move  k/↑ move  a add  e/Enter edit  d/x delete",
    "  c default colorscheme  b default background",
    "  l light override  n dark override  t toggle  r reload  q/Esc quit",
    "  draft line shows the entry you are currently editing",
  }, "\n"), vim.log.levels.INFO)
end

local function cursor_move(delta)
  _cursor = math.max(1, math.min(math.max(1, #ct.config.schedule), _cursor + delta))
  render()
end

local function close()
  clear_draft()
  if _win and api.nvim_win_is_valid(_win) then
    api.nvim_win_close(_win, true)
  end
  _win, _buf = nil, nil
end

local function desired_window_width(ui)
  local cols = current_columns()
  local width = table_width(cols) + 2
  local lines = {}
  vim.list_extend(lines, get_static_header(cols, ct.config.enabled))
  vim.list_extend(lines, draft_lines(cols))
  vim.list_extend(lines, footer_lines())
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end
  return math.min(math.max(width, MIN_WINDOW_WIDTH), math.max(MIN_WINDOW_WIDTH, ui.width - 4))
end

local function current_ui()
  local ui = api.nvim_list_uis()[1]
  if ui then
    return ui
  end
  return {
    width = math.max(vim.o.columns, MIN_WINDOW_WIDTH + 4),
    height = math.max(vim.o.lines - 2, 12),
  }
end

function M.open()
  if _win and api.nvim_win_is_valid(_win) then
    api.nvim_set_current_win(_win)
    return
  end

  _buf = api.nvim_create_buf(false, true)
  vim.bo[_buf].buftype = "nofile"
  vim.bo[_buf].bufhidden = "wipe"
  vim.bo[_buf].filetype = "colorful-times"
  vim.bo[_buf].modifiable = false

  local ui = current_ui()
  local width = desired_window_width(ui)
  local content_height = 11 + math.max(1, #ct.config.schedule)
  local height = math.min(math.max(12, content_height), math.floor(ui.height * 0.8))

  _win = api.nvim_open_win(_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((ui.height - height) / 2),
    col = math.floor((ui.width - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Colorful Times ",
    title_pos = "center",
  })

  _cursor = math.max(1, math.min(_cursor, math.max(1, #ct.config.schedule)))

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
