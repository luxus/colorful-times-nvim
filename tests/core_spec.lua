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
    vim.notify = function(msg, level)
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
    vim.notify = function(msg, level)
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
    local M = require("colorful-times")

    local notified = false
    local notify_msg = nil
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
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
    vim.notify = function(msg, level)
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
    vim.notify = function(msg, level)
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
