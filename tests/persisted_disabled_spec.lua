describe("core.setup persisted state when disabled", function()
  local core
  local plugin
  local state
  local orig_defer_fn
  local orig_load

  before_each(function()
    package.loaded["colorful-times.core"] = nil
    package.loaded["colorful-times"] = nil
    package.loaded["colorful-times.state"] = nil

    core = require("colorful-times.core")
    plugin = require("colorful-times")
    state = require("colorful-times.state")
    orig_defer_fn = vim.defer_fn
    orig_load = state.load

    vim.defer_fn = function(fn)
      fn()
    end
  end)

  after_each(function()
    vim.defer_fn = orig_defer_fn
    state.load = orig_load
    vim.api.nvim_clear_autocmds({ group = "ColorfulTimes" })
    package.loaded["colorful-times.core"] = nil
    package.loaded["colorful-times"] = nil
    package.loaded["colorful-times.state"] = nil
  end)

  it("merges persisted config even when setup starts disabled", function()
    local load_calls = 0
    state.load = function()
      load_calls = load_calls + 1
      return {
        enabled = false,
        schedule = {
          { start = "09:00", stop = "17:00", colorscheme = "persisted-theme", background = "light" },
        },
        default = {
          colorscheme = "persisted-default",
          background = "light",
          themes = {
            light = "persisted-light",
            dark = "persisted-dark",
          },
        },
      }
    end

    core.setup({
      enabled = false,
      persist = true,
      default = {
        colorscheme = "base-default",
        background = "dark",
        themes = {
          light = "base-light",
          dark = "base-dark",
        },
      },
      schedule = {},
    })

    assert.are.equal(1, load_calls)
    assert.is_false(plugin.config.enabled)
    assert.are.equal("persisted-default", plugin.config.default.colorscheme)
    assert.are.equal("persisted-light", plugin.config.default.themes.light)
    assert.are.equal("persisted-dark", plugin.config.default.themes.dark)
    assert.are.equal(1, #plugin.config.schedule)
    assert.are.equal("persisted-theme", plugin.config.schedule[1].colorscheme)
  end)
end)
