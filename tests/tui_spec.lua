describe("tui.open", function()
  local tui
  local plugin
  local orig_columns
  local orig_lines

  before_each(function()
    package.loaded["colorful-times.tui"] = nil
    package.loaded["colorful-times"] = nil

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
    local win = vim.api.nvim_get_current_win()
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    vim.o.columns = orig_columns
    vim.o.lines = orig_lines
    package.loaded["colorful-times.tui"] = nil
    package.loaded["colorful-times"] = nil
  end)

  it("opens in headless mode and renders current schedule data", function()
    vim.o.columns = 120
    vim.o.lines = 40

    assert.has_no.errors(function()
      tui.open()
    end)

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local text = table.concat(lines, "\n")

    assert.is_truthy(text:match("DEFAULT"))
    assert.is_truthy(text:match("LIGHT"))
    assert.is_truthy(text:match("DARK"))
    assert.is_truthy(text:match("07:00"))
    assert.is_truthy(text:match("18:00"))
    assert.is_truthy(text:match("tokyonight%-day"))
  end)

  it("adjusts the window width based on content width", function()
    vim.o.columns = 140
    vim.o.lines = 40

    tui.open()

    local compact_width = vim.api.nvim_win_get_width(0)
    vim.api.nvim_win_close(0, true)

    plugin.config.default.colorscheme = "very-long-default-colorscheme-name"
    plugin.config.default.themes.light = "very-long-light-colorscheme-name"
    plugin.config.schedule[1].colorscheme = "very-long-scheduled-colorscheme-name"

    tui.open()

    local expanded_width = vim.api.nvim_win_get_width(0)
    assert.is_true(compact_width >= 54)
    assert.is_true(expanded_width > compact_width)
  end)
end)
