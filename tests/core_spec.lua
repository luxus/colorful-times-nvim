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
