-- tests/system_spec.lua
describe("system.sysname", function()
  it("returns a non-empty string", function()
    local system = require("colorful-times.system")
    local name = system.sysname()
    assert.is_string(name)
    assert.is_true(#name > 0)
  end)

  it("caches the result (same value on second call)", function()
    local system = require("colorful-times.system")
    local a = system.sysname()
    local b = system.sysname()
    assert.are.equal(a, b)
  end)
end)

describe("system.get_background with function override", function()
  it("calls cb with the function's return value", function()
    local system = require("colorful-times.system")
    local M = require("colorful-times")
    M.config.system_background_detection = function() return "dark" end

    local result = nil
    system.get_background(function(bg) result = bg end, "light")

    -- system_background_detection function is called synchronously, so result is set immediately
    -- (the cb is called via vim.schedule, so we wait a tick)
    vim.wait(100, function() return result ~= nil end)
    assert.are.equal("dark", result)

    M.config.system_background_detection = nil
  end)
end)

describe("system.get_background fallback", function()
  it("calls cb with fallback on unsupported platform (mocked)", function()
    local system = require("colorful-times.system")
    -- Temporarily override sysname to simulate unsupported OS
    local orig_sysname = system.sysname
    system.sysname = function() return "Windows_NT" end

    local result = nil
    system.get_background(function(bg) result = bg end, "light")
    vim.wait(100, function() return result ~= nil end)
    assert.are.equal("light", result)

    system.sysname = orig_sysname
  end)
end)
