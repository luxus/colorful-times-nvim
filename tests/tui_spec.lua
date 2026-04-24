local function clear_colorful_times_modules()
  for name in pairs(package.loaded) do
    if name == "colorful-times" or name:match("^colorful%-times%.") then
      package.loaded[name] = nil
    end
  end
end

local function buffer_text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local function line_number(pattern)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for idx, line in ipairs(lines) do
    if line:find(pattern, 1, true) then
      return idx
    end
  end
end

local function feed(keys)
  local termcoded = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(termcoded, "x", false)
  vim.wait(20)
end

describe("tui.open", function()
  local tui
  local plugin
  local orig_columns
  local orig_lines

  before_each(function()
    clear_colorful_times_modules()

    plugin = require("colorful-times")
    tui = require("colorful-times.tui")

    plugin.config.enabled = true
    plugin.config.default.colorscheme = "kanagawa"
    plugin.config.default.background = "system"
    plugin.config.default.themes = {
      light = "dayfox",
      dark = "nightfox",
    }
    plugin.config.schedule = {
      {
        start = "07:00",
        stop = "18:00",
        colorscheme = "tokyonight-day",
        background = "light",
      },
    }

    orig_columns = vim.o.columns
    orig_lines = vim.o.lines
  end)

  after_each(function()
    pcall(function()
      tui.close()
    end)
    vim.o.columns = orig_columns
    vim.o.lines = orig_lines
    pcall(vim.api.nvim_clear_autocmds, { group = "ColorfulTimes" })
    clear_colorful_times_modules()
  end)

  it("opens in headless mode and renders current schedule data", function()
    vim.o.columns = 120
    vim.o.lines = 40

    assert.has_no.errors(function()
      tui.open()
    end)

    local text = buffer_text()

    assert.is_truthy(text:match("DEFAULT"))
    assert.is_truthy(text:match("Light override"))
    assert.is_truthy(text:match("Dark override"))
    assert.is_truthy(text:match("07:00"))
    assert.is_truthy(text:match("18:00"))
    assert.is_truthy(text:match("tokyonight%-day"))
  end)

  it("opens a wide enough window for framed panels", function()
    vim.o.columns = 140
    vim.o.lines = 40

    tui.open()

    local width = vim.api.nvim_win_get_width(0)
    assert.is_true(width >= 100)
    assert.is_truthy(buffer_text():match("● SCHEDULE"))
    assert.is_truthy(buffer_text():match("─"))
  end)

  it("keeps rendered lines within the float on narrower editors", function()
    vim.o.columns = 80
    vim.o.lines = 30

    tui.open()

    local width = vim.api.nvim_win_get_width(0)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, line in ipairs(lines) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= width)
    end
  end)

  it("renders the inline add drawer in the same buffer", function()
    vim.o.columns = 120
    vim.o.lines = 40

    tui.open()
    feed("a")

    local text = buffer_text()
    assert.is_truthy(text:match("ADD ENTRY"))
    assert.is_truthy(text:match("Preview now"))
    assert.is_truthy(text:match("START"))
    assert.is_truthy(text:match("THEME"))
  end)

  it("renders the inline theme selector in the same buffer", function()
    vim.o.columns = 120
    vim.o.lines = 40

    tui.open()
    feed("a")
    feed("<Tab><Tab><CR>")

    local text = buffer_text()
    assert.is_truthy(text:match("THEME  type to filter"))
    assert.is_truthy(text:match("Preview now"))
    assert.is_true(line_number("Preview now") > line_number("THEME  type to filter"))
  end)

  it("updates the preview line while moving through theme choices", function()
    vim.o.columns = 120
    vim.o.lines = 40

    tui.open()
    feed("a")
    feed("<Tab><Tab><CR>")

    local app = tui._app()
    local next_theme = app.state.theme_items[2]
    assert.is_not_nil(next_theme)

    feed("j")

    assert.are.equal(next_theme, app.state.draft.colorscheme)
    assert.is_truthy(buffer_text():find("Preview now  theme " .. next_theme, 1, true))
  end)

  it("shows the complete theme filter text", function()
    vim.o.columns = 120
    vim.o.lines = 40

    tui.open()
    feed("a")
    feed("<Tab><Tab><CR>")
    feed("cat")

    assert.is_truthy(buffer_text():match("THEME  type to filter  %[cat%]"))
  end)

  it("accepts common colorscheme name characters in the theme filter", function()
    vim.o.columns = 120
    vim.o.lines = 40

    tui.open()
    feed("a")
    feed("<Tab><Tab><CR>")
    feed("paper")

    assert.are.equal("paper", tui._app().state.theme_filter)
    assert.is_truthy(buffer_text():match("THEME  type to filter  %[paper%]"))
  end)

  it("replaces time fields and cycles background", function()
    vim.o.columns = 120
    vim.o.lines = 40

    tui.open()
    feed("a")

    local app = tui._app()
    feed("12:34")
    assert.are.equal("12:34", app.state.draft.start)

    feed("j")
    assert.are.equal("stop", require("colorful-times.tui.state").active_field(app.state))
    feed("23:45")
    assert.are.equal("23:45", app.state.draft.stop)

    feed("j")
    assert.are.equal("colorscheme", require("colorful-times.tui.state").active_field(app.state))
    feed("j")
    assert.are.equal("background", require("colorful-times.tui.state").active_field(app.state))

    local before = app.state.draft.background
    feed("l")
    assert.are_not.equal(before, app.state.draft.background)
  end)

  it("normalizes short time input on field change and places cursor on the time value", function()
    vim.o.columns = 120
    vim.o.lines = 40

    tui.open()
    feed("a")

    local app = tui._app()
    feed("14")
    local before = vim.api.nvim_win_get_cursor(0)
    assert.is_true(before[2] > 10)

    feed("j")
    assert.are.equal("14:00", app.state.draft.start)
  end)

  it("asks before discarding unsaved schedule edits", function()
    vim.o.columns = 120
    vim.o.lines = 40

    tui.open()
    feed("<CR>")
    feed("12:00")
    feed("<Esc>")

    local app = tui._app()
    assert.is_true(app.state.pending_discard)
    assert.is_truthy(buffer_text():match("Discard unsaved changes"))

    feed("n")
    assert.is_false(app.state.pending_discard)
    assert.are.equal("edit", app.state.mode)

    feed("<Esc>")
    feed("y")

    assert.are.equal("browse", app.state.mode)
    assert.are.equal("07:00", plugin.config.schedule[1].start)
  end)

  it("switches between defaults and schedule with tab and edits defaults directly", function()
    vim.o.columns = 120
    vim.o.lines = 40

    tui.open()
    feed("<Tab>")
    assert.are.equal("defaults", tui._app().state.section)

    feed("<CR>")
    assert.is_truthy(buffer_text():match("THEME  type to filter"))
    assert.is_truthy(buffer_text():match("EDIT DEFAULT"))

    feed("<Esc>")
    feed("j")
    feed("<CR>")
    assert.is_truthy(buffer_text():match("BACKGROUND"))
  end)

  it("toggles the current theme hold from browse mode", function()
    vim.o.columns = 120
    vim.o.lines = 40

    tui.open()
    feed("H")

    local status = require("colorful-times.core").status()
    assert.is_true(status.pinned)
    assert.are.equal("session_pin", status.source)
    assert.is_truthy(buffer_text():match("Held current theme"))

    feed("H")
    status = require("colorful-times.core").status()
    assert.is_false(status.pinned)
    assert.is_truthy(buffer_text():match("Session hold released"))
  end)

  it("shows delete confirmation as a centered warning", function()
    vim.o.columns = 140
    vim.o.lines = 40

    tui.open()
    feed("d")

    local text = buffer_text()
    assert.is_truthy(text:match("⚠"))
    assert.is_truthy(text:match("Delete 07:00%-18:00 tokyonight%-day"))
    assert.is_truthy(text:match("y delete / n or Esc cancel"))
  end)
end)

describe("tui.view_model add defaults", function()
  before_each(function()
    clear_colorful_times_modules()
  end)

  after_each(function()
    clear_colorful_times_modules()
  end)

  it("uses empty-schedule defaults with current resolved theme/background", function()
    local view_model = require("colorful-times.tui.view_model")
    local config = {
      default = { colorscheme = "fallback", background = "system" },
      schedule = {},
    }
    local defaults = view_model.add_defaults(config, {
      colorscheme = "active-theme",
      background = "dark",
    })

    assert.are.equal("08:00", defaults.start)
    assert.are.equal("18:00", defaults.stop)
    assert.are.equal("active-theme", defaults.colorscheme)
    assert.are.equal("dark", defaults.background)
  end)

  it("uses the displayed chronological schedule edges", function()
    local view_model = require("colorful-times.tui.view_model")
    local config = {
      default = { colorscheme = "fallback", background = "system" },
      schedule = {
        { start = "18:00", stop = "06:00", colorscheme = "night", background = "dark" },
        { start = "08:00", stop = "12:00", colorscheme = "morning", background = "light" },
      },
    }
    local defaults = view_model.add_defaults(config, {
      colorscheme = "active-theme",
      background = "light",
    })

    assert.are.equal("06:00", defaults.start)
    assert.are.equal("08:00", defaults.stop)
    assert.are.equal("active-theme", defaults.colorscheme)
    assert.are.equal("light", defaults.background)
  end)
end)

describe("tui.preview", function()
  local orig_background

  before_each(function()
    clear_colorful_times_modules()
    orig_background = vim.o.background
    vim.o.background = "dark"
  end)

  after_each(function()
    require("colorful-times.tui.preview").restore()
    vim.o.background = orig_background
    clear_colorful_times_modules()
  end)

  it("restores the captured background when canceled", function()
    local preview = require("colorful-times.tui.preview")

    preview.begin()
    preview.apply("default", "light")
    assert.is_true(vim.wait(100, function()
      return vim.o.background == "light"
    end))

    preview.restore()
    assert.is_true(vim.wait(100, function()
      return vim.o.background == "dark"
    end))
  end)
end)
