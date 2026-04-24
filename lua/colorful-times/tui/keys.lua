-- lua/colorful-times/tui/keys.lua
-- Mode-aware keymap registration.

local M = {}
local actions = require("colorful-times.tui.actions")
local ui_state = require("colorful-times.tui.state")

local function in_theme_select(app)
  return app.state.mode == ui_state.modes.theme_select
end

local function map(buf, key, fn)
  vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
end

local function char_or(app, char, fn)
  return function()
    if in_theme_select(app) then
      actions.input_char(app, char)
      return
    end
    if app.state.mode == ui_state.modes.browse then
      fn()
    end
  end
end

function M.setup(app)
  local buf = app.buf

  map(buf, "j", function()
    actions.move(app, 1)
  end)
  map(buf, "<Down>", function()
    actions.move(app, 1)
  end)
  map(buf, "k", function()
    actions.move(app, -1)
  end)
  map(buf, "<Up>", function()
    actions.move(app, -1)
  end)
  map(buf, "<Right>", function()
    actions.right(app)
  end)
  map(buf, "<Left>", function()
    actions.left(app)
  end)
  map(buf, "<Tab>", function()
    actions.next_field(app)
  end)
  map(buf, "<S-Tab>", function()
    actions.prev_field(app)
  end)
  map(buf, "<CR>", function()
    actions.confirm(app)
  end)
  map(buf, "<BS>", function()
    actions.backspace(app)
  end)
  map(buf, "<Del>", function()
    actions.backspace(app)
  end)
  map(buf, "<Esc>", function()
    actions.close_or_cancel(app)
  end)

  map(
    buf,
    "a",
    char_or(app, "a", function()
      actions.begin_add(app)
    end)
  )
  map(
    buf,
    "e",
    char_or(app, "e", function()
      actions.confirm(app)
    end)
  )
  map(
    buf,
    "d",
    char_or(app, "d", function()
      actions.request_delete(app)
    end)
  )
  map(
    buf,
    "x",
    char_or(app, "x", function()
      actions.request_delete(app)
    end)
  )
  map(
    buf,
    "H",
    char_or(app, "H", function()
      actions.toggle_hold(app)
    end)
  )
  map(buf, "O", function()
    actions.toggle_hold(app)
  end)
  map(
    buf,
    "u",
    char_or(app, "u", function()
      actions.toggle_hold(app)
    end)
  )
  map(
    buf,
    "t",
    char_or(app, "t", function()
      actions.toggle(app)
    end)
  )
  map(
    buf,
    "r",
    char_or(app, "r", function()
      actions.reload(app)
    end)
  )
  map(
    buf,
    "y",
    function()
      if app.state.pending_delete or app.state.pending_discard then
        actions.confirm_prompt(app)
        return
      end
      if in_theme_select(app) then
        actions.input_char(app, "y")
      end
    end
  )
  map(
    buf,
    "n",
    function()
      if app.state.pending_delete or app.state.pending_discard then
        actions.cancel(app)
        return
      end
      if in_theme_select(app) then
        actions.input_char(app, "n")
      end
    end
  )
  map(buf, "?", function()
    actions.help(app)
  end)
  map(
    buf,
    "q",
    char_or(app, "q", function()
      actions.close_or_cancel(app)
    end)
  )

  map(buf, "S", function()
    actions.save(app)
  end)
  map(buf, "h", function()
    if in_theme_select(app) then
      actions.input_char(app, "h")
    else
      actions.left(app)
    end
  end)
  map(buf, "l", function()
    if in_theme_select(app) then
      actions.input_char(app, "l")
    else
      actions.right(app)
    end
  end)

  local reserved = {
    a = true,
    d = true,
    e = true,
    h = true,
    j = true,
    k = true,
    l = true,
    n = true,
    q = true,
    r = true,
    t = true,
    u = true,
    x = true,
    y = true,
  }

  local chars = {
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    ":",
    "-",
    "_",
    ".",
  }
  for byte = string.byte("a"), string.byte("z") do
    local char = string.char(byte)
    if not reserved[char] then
      chars[#chars + 1] = char
    end
  end

  for _, char in ipairs(chars) do
    map(buf, char, function()
      actions.input_char(app, char)
    end)
  end
end

return M
