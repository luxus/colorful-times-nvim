-- tests/core_spec.lua
-- Core tests use mocked schedule + system modules to avoid real timers/spawns.

describe("core module loading", function()
  it("loads without error", function()
    assert.has_no.errors(function()
      require("colorful-times.core")
    end)
  end)
end)

describe("core.setup", function()
  it("sets enabled state from config", function()
    local M = require("colorful-times")
    local core = require("colorful-times.core")

    M.config.enabled = true
    M.config.schedule = {}
    M.config.default.background = "dark"
    M.config.default.colorscheme = "default"

    -- Should not throw even with no schedule
    assert.has_no.errors(function()
      core.setup(M.config)
    end)
  end)
end)

describe("core.toggle", function()
  it("flips M.config.enabled", function()
    local M    = require("colorful-times")
    local core = require("colorful-times.core")

    M.config.enabled = true
    core.setup(M.config)

    local before = M.config.enabled
    core.toggle()
    assert.are.equal(not before, M.config.enabled)

    core.toggle()  -- restore
    assert.are.equal(before, M.config.enabled)
  end)
end)

describe("core.setup validation", function()
  before_each(function()
    -- Reset module state before each test
    package.loaded["colorful-times.core"] = nil
    package.loaded["colorful-times"] = nil
  end)

  it("rejects invalid enabled type", function()
    local core = require("colorful-times.core")
    local M = require("colorful-times")

    -- Store original config
    local orig_config = vim.deepcopy(M.config)

    -- Attempt to set enabled to a string
    local notified = false
    local notify_msg = nil
    local orig_notify = vim.notify
    vim.notify = function(msg, _level)
      notified = true
      notify_msg = msg
    end

    core.setup({ enabled = "yes" })

    vim.notify = orig_notify

    assert.is_true(notified)
    assert.is_truthy(notify_msg:match("enabled must be a boolean"))
    -- Config should not have been modified
    assert.are.equal(orig_config.enabled, M.config.enabled)
  end)

  it("rejects invalid refresh_time", function()
    local core = require("colorful-times.core")
    local M = require("colorful-times")

    local orig_refresh_time = M.config.refresh_time

    local notified = false
    local notify_msg = nil
    local orig_notify = vim.notify
    vim.notify = function(msg, _level)
      notified = true
      notify_msg = msg
    end

    core.setup({ refresh_time = 500 })

    vim.notify = orig_notify

    assert.is_true(notified)
    assert.is_truthy(notify_msg:match("refresh_time must be an integer >= 1000"))
    assert.are.equal(orig_refresh_time, M.config.refresh_time)
  end)

  it("rejects invalid schedule entry", function()
    local core = require("colorful-times.core")

    local notified = false
    local notify_msg = nil
    local orig_notify = vim.notify
    vim.notify = function(msg, _level)
      notified = true
      notify_msg = msg
    end

    core.setup({
      schedule = {
        { start = "invalid", stop = "06:00", colorscheme = "morning" }
      }
    })

    vim.notify = orig_notify

    assert.is_true(notified)
    assert.is_truthy(notify_msg:match("schedule"))
    assert.is_truthy(notify_msg:match("invalid start time"))
  end)

  it("rejects invalid default.background", function()
    local core = require("colorful-times.core")
    local M = require("colorful-times")

    local orig_background = M.config.default.background

    local notified = false
    local notify_msg = nil
    local orig_notify = vim.notify
    vim.notify = function(msg, _level)
      notified = true
      notify_msg = msg
    end

    core.setup({ default = { background = "blue" } })

    vim.notify = orig_notify

    assert.is_true(notified)
    assert.is_truthy(notify_msg:match("background must be"))
    assert.are.equal(orig_background, M.config.default.background)
  end)

  it("accepts valid configuration", function()
    local core = require("colorful-times.core")
    local M = require("colorful-times")

    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(_msg, level)
      if level == vim.log.levels.ERROR then
        notified = true
      end
    end

    core.setup({
      enabled = true,
      refresh_time = 10000,
      persist = false,
      default = { background = "dark" },
      schedule = {
        { start = "06:00", stop = "18:00", colorscheme = "day", background = "light" }
      }
    })

    vim.notify = orig_notify

    assert.is_false(notified)
    assert.are.equal(true, M.config.enabled)
    assert.are.equal(10000, M.config.refresh_time)
    assert.are.equal(false, M.config.persist)
    assert.are.equal("dark", M.config.default.background)
  end)
end)

describe("core.resolve_theme wall clock", function()
  local core
  local plugin
  local orig_os_date

  before_each(function()
    package.loaded["colorful-times.core"] = nil
    package.loaded["colorful-times"] = nil
    core = require("colorful-times.core")
    plugin = require("colorful-times")
    orig_os_date = os.date
  end)

  after_each(function()
    rawset(os, "date", orig_os_date)
    package.loaded["colorful-times.core"] = nil
    package.loaded["colorful-times"] = nil
  end)

  it("resolves the active schedule entry using wall-clock time", function()
    rawset(os, "date", function()
      return { hour = 12, min = 0 }
    end)

    plugin.config.enabled = true
    plugin.config.default.background = "dark"
    plugin.config.schedule = {
      {
        start = "11:59",
        stop = "12:01",
        colorscheme = "wall-clock-theme",
        background = "light",
      },
    }

    local colorscheme, background = core.resolve_theme()
    assert.are.equal("wall-clock-theme", colorscheme)
    assert.are.equal("light", background)
  end)

  it("keeps an explicit schedule colorscheme when the schedule entry uses system background", function()
    rawset(os, "date", function()
      return { hour = 22, min = 30 }
    end)

    plugin.config.enabled = true
    plugin.config.default.background = "system"
    plugin.config.default.colorscheme = "base-theme"
    plugin.config.default.themes = {
      light = "base-light",
      dark = "base-dark",
    }
    plugin.config.schedule = {
      {
        start = "22:29",
        stop = "22:31",
        colorscheme = "scheduled-system-theme",
        background = "system",
      },
    }

    local colorscheme, background, use_default_overrides = core.resolve_theme()
    assert.are.equal("scheduled-system-theme", colorscheme)
    assert.are.equal("system", background)
    assert.is_false(use_default_overrides)
  end)
end)

describe("core.setup regression coverage", function()
  local core
  local plugin
  local state
  local orig_notify
  local orig_defer_fn
  local orig_save
  local orig_os_date

  before_each(function()
    package.loaded["colorful-times.core"] = nil
    package.loaded["colorful-times"] = nil
    package.loaded["colorful-times.state"] = nil
    core = require("colorful-times.core")
    plugin = require("colorful-times")
    state = require("colorful-times.state")
    orig_notify = vim.notify
    orig_defer_fn = vim.defer_fn
    orig_save = state.save
    orig_os_date = os.date
  end)

  after_each(function()
    vim.notify = orig_notify
    vim.defer_fn = orig_defer_fn
    state.save = orig_save
    rawset(os, "date", orig_os_date)
    vim.api.nvim_clear_autocmds({ group = "ColorfulTimes" })
    package.loaded["colorful-times.core"] = nil
    package.loaded["colorful-times"] = nil
    package.loaded["colorful-times.state"] = nil
  end)

  it("rejects schedule entries where start equals stop", function()
    local orig_config = vim.deepcopy(plugin.config)
    local notified = false
    local notify_msg

    vim.notify = function(msg)
      notified = true
      notify_msg = msg
    end

    core.setup({
      schedule = {
        { start = "06:00", stop = "06:00", colorscheme = "test" },
      },
    })

    assert.is_true(notified)
    assert.is_truthy(notify_msg:match("start and stop times must differ"))
    assert.are.same(orig_config, plugin.config)
  end)

  it("registers focus autocmds even when disabled", function()
    plugin.config.enabled = true

    core.setup({ enabled = false })

    local autocmds = vim.api.nvim_get_autocmds({ group = "ColorfulTimes" })
    local events = {}
    for _, autocmd in ipairs(autocmds) do
      events[autocmd.event] = true
    end

    assert.is_true(events.FocusLost)
    assert.is_true(events.FocusGained)
  end)

  it("skips state loading when persist is false", function()
    local calls = 0
    local orig_load = state.load

    state.load = function()
      calls = calls + 1
      return {}
    end
    vim.defer_fn = function(fn)
      fn()
    end

    core.setup({
      enabled = true,
      persist = false,
      default = {
        background = "light",
        colorscheme = "default",
      },
      schedule = {},
    })

    state.load = orig_load
    assert.are.equal(0, calls)
  end)

  it("reload rebuilds config from the persisted state on disk", function()
    local load_calls = 0
    local orig_load = state.load

    state.load = function()
      load_calls = load_calls + 1
      return {
        enabled = true,
        schedule = {
          { start = "09:00", stop = "17:00", colorscheme = "persisted-theme", background = "light" },
        },
        default = {
          colorscheme = "persisted-default",
          background = "system",
          themes = {
            light = "persisted-light",
            dark = "persisted-dark",
          },
        },
      }
    end
    vim.defer_fn = function(fn)
      fn()
    end

    core.setup({
      enabled = true,
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

    plugin.config.default.colorscheme = "mutated-default"
    plugin.config.default.themes.light = "mutated-light"
    plugin.config.schedule = {
      { start = "01:00", stop = "02:00", colorscheme = "mutated-schedule", background = "dark" },
    }

    core.reload()

    state.load = orig_load

    assert.are.equal(2, load_calls)
    assert.are.equal("persisted-default", plugin.config.default.colorscheme)
    assert.are.equal("persisted-light", plugin.config.default.themes.light)
    assert.are.equal("persisted-dark", plugin.config.default.themes.dark)
    assert.are.equal("persisted-theme", plugin.config.schedule[1].colorscheme)
  end)

  it("toggle persists the current state", function()
    local saved

    state.save = function(data)
      saved = vim.deepcopy(data)
    end

    plugin.config.enabled = true
    plugin.config.persist = true
    plugin.config.refresh_time = 5000
    plugin.config.default = {
      colorscheme = "default-theme",
      background = "system",
      themes = {
        light = "day-theme",
        dark = "night-theme",
      },
    }
    plugin.config.schedule = {
      { start = "08:00", stop = "18:00", colorscheme = "day", background = "light" },
    }

    core.toggle()

    assert.is_not_nil(saved)
    assert.is_false(saved.enabled)
    assert.are.equal("default-theme", saved.default.colorscheme)
    assert.are.equal("day-theme", saved.default.themes.light)
    assert.are.equal("night-theme", saved.default.themes.dark)
    assert.are.equal("day", saved.schedule[1].colorscheme)
  end)

  it("enables and disables directly while persisting the new state", function()
    local saved = {}

    state.save = function(data)
      saved[#saved + 1] = vim.deepcopy(data)
    end

    plugin.config.enabled = false
    plugin.config.persist = true
    plugin.config.default.background = "dark"
    plugin.config.default.colorscheme = "default-theme"
    plugin.config.schedule = {}

    core.enable()
    core.disable()

    assert.is_true(saved[1].enabled)
    assert.is_false(saved[2].enabled)
  end)

  it("reports resolved status information", function()
    plugin.config.enabled = true
    plugin.config.persist = true
    plugin.config.refresh_time = 5000
    plugin.config.default = {
      colorscheme = "base-theme",
      background = "system",
      themes = {
        light = "day-theme",
        dark = "night-theme",
      },
    }
    plugin.config.schedule = {}

    rawset(os, "date", function()
      return { hour = 9, min = 0 }
    end)

    vim.o.background = "light"
    local status = core.status()

    assert.is_true(status.enabled)
    assert.is_true(status.persist)
    assert.are.equal("default", status.source)
    assert.are.equal("system", status.requested_background)
    assert.are.equal("light", status.background)
    assert.are.equal("day-theme", status.colorscheme)
  end)
end)

describe("core polling hardening", function()
  local orig_defer_fn
  local orig_new_timer
  local poll_callback
  local detection_callback
  local get_background_calls

  before_each(function()
    package.loaded["colorful-times.core"] = nil
    package.loaded["colorful-times"] = nil
    package.loaded["colorful-times.system"] = nil

    orig_defer_fn = vim.defer_fn
    vim.defer_fn = function(fn)
      fn()
    end

    orig_new_timer = vim.uv.new_timer
    vim.uv.new_timer = function()
      local timer = {}
      function timer:start(_, _, cb)
        poll_callback = cb
      end
      function timer:stop() end
      function timer:close() end
      function timer:is_closing()
        return false
      end
      return timer
    end

    local system = require("colorful-times.system")
    get_background_calls = 0
    system.has_detection = function()
      return true
    end
    system.get_background = function(cb)
      get_background_calls = get_background_calls + 1
      detection_callback = cb
    end
  end)

  after_each(function()
    vim.defer_fn = orig_defer_fn
    vim.uv.new_timer = orig_new_timer
    vim.api.nvim_clear_autocmds({ group = "ColorfulTimes" })
    package.loaded["colorful-times.core"] = nil
    package.loaded["colorful-times"] = nil
    package.loaded["colorful-times.system"] = nil
  end)

  it("does not start overlapping poll detections", function()
    local core = require("colorful-times.core")
    local plugin = require("colorful-times")

    plugin.config.enabled = true
    plugin.config.persist = false
    plugin.config.refresh_time = 5000
    plugin.config.default = {
      colorscheme = "base-theme",
      background = "system",
      themes = { light = nil, dark = nil },
    }
    plugin.config.schedule = {}

    core.setup(plugin.config)
    detection_callback("dark") -- finish initial apply_colorscheme detection

    assert.is_function(poll_callback)

    poll_callback()
    assert.are.equal(2, get_background_calls)

    poll_callback()
    assert.are.equal(2, get_background_calls)

    detection_callback("light")
    poll_callback()
    assert.are.equal(4, get_background_calls)
  end)
end)
