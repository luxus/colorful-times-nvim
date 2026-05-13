-- lua/colorful-times/tui/actions.lua
-- Adapter that runs TUI action policy effect intents.

local M = {}
local ct = require("colorful-times")
local core = require("colorful-times.core")
local preview = require("colorful-times.tui.preview")
local action_policy = require("colorful-times.tui.action_policy")

local function run_effects(app, effects)
  for _, effect in ipairs(effects or {}) do
    if effect.kind == "render" then
      if app.render then app.render() end
    elseif effect.kind == "message" then
      app.state.message = effect.text
    elseif effect.kind == "preview_begin" then
      preview.begin()
    elseif effect.kind == "preview_apply" then
      preview.apply_target(effect.target)
    elseif effect.kind == "preview_restore" then
      preview.restore()
    elseif effect.kind == "preview_commit" then
      preview.commit()
    elseif effect.kind == "save_refresh" then
      core.save_state()
      if core.refresh then core.refresh() else core.reload() end
    elseif effect.kind == "core_refresh" then
      if core.refresh then core.refresh() else core.reload() end
    elseif effect.kind == "core_reload" then
      core.reload()
    elseif effect.kind == "pin_session" then
      core.pin_session(effect.colorscheme, effect.background, effect.resolved_background)
    elseif effect.kind == "unpin_session" then
      core.unpin_session()
    elseif effect.kind == "toggle_enabled" then
      core.toggle()
    elseif effect.kind == "toggle_tui_colors" then
      core.toggle_tui_colors()
      require("colorful-times.tui.highlights").setup(app.win, ct.config.tui_colors)
      if app.render then app.render() end
    elseif effect.kind == "close" then
      if app.close then app.close() end
    elseif effect.kind == "notify_help" then
      vim.notify(effect.text, vim.log.levels.INFO)
    end
  end
end

local function dispatch(app, name, ...)
  local effects = action_policy.dispatch({
    state = app.state,
    config = ct.config,
    status = core.status,
    preview_target = function(req) return core.preview_target(req) end,
    current_background = vim.o.background,
    close = function() if app.close then app.close() end end,
  }, name, ...)
  run_effects(app, effects)
end

function M.move(app, delta) dispatch(app, "move", delta) end
function M.next_field(app) dispatch(app, "next_field") end
function M.prev_field(app) dispatch(app, "prev_field") end
function M.begin_add(app) dispatch(app, "begin_add") end
function M.begin_edit(app) dispatch(app, "begin_edit") end
function M.cancel(app) dispatch(app, "cancel") end
function M.save(app) dispatch(app, "save") end
function M.enter_theme_select(app) dispatch(app, "enter_theme_select") end
function M.confirm_theme(app) dispatch(app, "confirm_theme") end
function M.enter_bg_select(app) dispatch(app, "enter_bg_select") end
function M.begin_default_colorscheme(app) dispatch(app, "begin_default_colorscheme") end
function M.begin_default_background(app) dispatch(app, "begin_default_background") end
function M.begin_theme_override(app, kind) dispatch(app, "begin_theme_override", kind) end
function M.confirm_bg(app) dispatch(app, "confirm_bg") end
function M.confirm(app) dispatch(app, "confirm") end
function M.confirm_prompt(app) dispatch(app, "confirm_prompt") end
function M.cycle_background(app, delta) dispatch(app, "cycle_background", delta) end
function M.input_char(app, char) dispatch(app, "input_char", char) end
function M.backspace(app) dispatch(app, "backspace") end
function M.request_delete(app) dispatch(app, "request_delete") end
function M.confirm_delete(app) dispatch(app, "confirm_delete") end
function M.toggle_hold(app) dispatch(app, "toggle_hold") end
function M.pin_browse(app) dispatch(app, "pin_browse") end
function M.pin_draft(app) dispatch(app, "pin_draft") end
function M.unpin(app) dispatch(app, "unpin") end
function M.toggle(app) dispatch(app, "toggle") end
function M.toggle_tui_colors(app) dispatch(app, "toggle_tui_colors") end
function M.reload(app) dispatch(app, "reload") end
function M.left(app) dispatch(app, "left") end
function M.right(app) dispatch(app, "right") end
function M.close_or_cancel(app) dispatch(app, "close_or_cancel") end

function M.help()
  vim.notify(
    table.concat({
      "colorful-times keys:",
      "  browse: Tab switches Defaults/Schedule, j/k move, Enter edit, a add schedule, d delete schedule, H hold/release session theme, q close",
      "  edit: Tab/j/k fields, type 0-9/: replaces active time, h/l cycles background on bg field, O session hold, S save, Esc cancel",
      "  theme selector: type filter, Backspace erase, j/k move, Enter choose, Esc cancel",
    }, "\n"),
    vim.log.levels.INFO
  )
end

return M
