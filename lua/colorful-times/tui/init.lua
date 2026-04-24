-- lua/colorful-times/tui/init.lua
-- Root lifecycle for the Colorful Times one-float TUI.

local M = {}
local api = vim.api

local state_mod = require("colorful-times.tui.state")
local layout = require("colorful-times.tui.layout")
local render = require("colorful-times.tui.render")
local highlights = require("colorful-times.tui.highlights")
local keys = require("colorful-times.tui.keys")
local preview = require("colorful-times.tui.preview")

local app = nil

local function valid_window(current)
  return current and current.win and api.nvim_win_is_valid(current.win)
end

local function close_app(current)
  current = current or app
  if not current then
    return
  end

  if preview.active() then
    preview.restore()
  end

  if current.win and api.nvim_win_is_valid(current.win) then
    api.nvim_win_close(current.win, true)
  end

  if app == current then
    app = nil
  end
end

local function create_buffer()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "colorful-times"
  vim.bo[buf].modifiable = false
  vim.bo[buf].swapfile = false
  return buf
end

function M.open()
  if valid_window(app) then
    api.nvim_set_current_win(app.win)
    return
  end

  local buf = create_buffer()
  local win = api.nvim_open_win(buf, true, layout.window_config({ "Colorful Times" }))

  app = {
    buf = buf,
    win = win,
    state = state_mod.new(),
  }

  function app.render()
    render.draw(app)
  end

  function app.close()
    close_app(app)
  end

  highlights.setup(win)
  keys.setup(app)

  api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if preview.active() then
        preview.restore()
      end
      if app and app.buf == buf then
        app = nil
      end
    end,
  })

  app.render()
end

function M.close()
  close_app(app)
end

function M._app()
  return app
end

return M
