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

  it("falls back when the function override errors", function()
    local system = require("colorful-times.system")
    local M = require("colorful-times")
    local orig_notify = vim.notify
    local result
    local notified = false

    M.config.system_background_detection = function()
      error("boom")
    end
    vim.notify = function()
      notified = true
    end

    system.get_background(function(bg) result = bg end, "light")

    vim.wait(100, function() return result ~= nil end)
    vim.notify = orig_notify
    M.config.system_background_detection = nil

    assert.is_true(notified)
    assert.are.equal("light", result)
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

describe("system.get_background with system_background_detection_script", function()
  local uv = vim.uv
  local M = require("colorful-times")
  local system = require("colorful-times.system")
  local orig_sysname = system.sysname
  local orig_wait = vim.wait
  local tmpdir = nil

  before_each(function()
    -- Mock Linux for these tests
    system.sysname = function() return "Linux" end
    vim.wait = function(timeout, ...)
      return orig_wait(math.max(timeout, 2000), ...)
    end
    -- Create temp directory for test scripts
    tmpdir = uv.fs_mkdtemp("/tmp/colorful_times_test_XXXXXX")
  end)

  after_each(function()
    system.sysname = orig_sysname
    vim.wait = orig_wait
    M.config.system_background_detection_script = nil
    -- Clean up temp directory
    if tmpdir then
      local handle = uv.fs_scandir(tmpdir)
      while handle do
        local name, typ = uv.fs_scandir_next(handle)
        if not name then break end
        uv.fs_unlink(tmpdir .. "/" .. name)
      end
      uv.fs_rmdir(tmpdir)
      tmpdir = nil
    end
  end)

  it("executes custom script and returns dark on exit 0", function()
    local script_path = tmpdir .. "/dark_script.sh"
    local f = assert(io.open(script_path, "w"))
    f:write("#!/bin/sh\nexit 0")
    f:close()
    assert(uv.fs_chmod(script_path, tonumber("755", 8)))

    -- Verify the file exists and is executable
    local stat = uv.fs_stat(script_path)
    assert.is_not_nil(stat, "script should exist")
    local bit = require("bit")
    assert.is_true(bit.band(stat.mode, tonumber("111", 8)) ~= 0, "script should be executable")

    M.config.system_background_detection_script = script_path

    local result = nil
    system.get_background(function(bg) result = bg end, "light")
    vim.wait(500, function() return result ~= nil end)
    assert.is_not_nil(result, "callback should have been called")
    assert.are.equal("dark", result)
  end)

  it("executes custom script and returns light on exit 1", function()
    local script_path = tmpdir .. "/light_script.sh"
    local f = assert(io.open(script_path, "w"))
    f:write("#!/bin/sh\nexit 1")
    f:close()
    assert(uv.fs_chmod(script_path, tonumber("755", 8)))

    M.config.system_background_detection_script = script_path

    local result = nil
    system.get_background(function(bg) result = bg end, "dark")
    vim.wait(500, function() return result ~= nil end)
    assert.is_not_nil(result, "callback should have been called")
    assert.are.equal("light", result)
  end)

  it("falls back to default when script does not exist", function()
    M.config.system_background_detection_script = "/nonexistent/script.sh"

    local result = nil
    system.get_background(function(bg) result = bg end, "dark")
    vim.wait(100, function() return result ~= nil end)
    -- Should fallback to the provided fallback value
    assert.are.equal("dark", result)
  end)

  it("falls back to default when script is not executable", function()
    local script_path = tmpdir .. "/not_executable.sh"
    local f = assert(io.open(script_path, "w"))
    f:write("#!/bin/sh\nexit 0")
    f:close()
    -- Not setting executable permission
    assert(uv.fs_chmod(script_path, tonumber("644", 8)))

    M.config.system_background_detection_script = script_path

    local result = nil
    system.get_background(function(bg) result = bg end, "light")
    vim.wait(100, function() return result ~= nil end)
    -- Should fallback to the provided fallback value
    assert.are.equal("light", result)
  end)

  it("falls back when script path is a directory", function()
    M.config.system_background_detection_script = tmpdir

    local result = nil
    system.get_background(function(bg) result = bg end, "light")
    vim.wait(100, function() return result ~= nil end)
    -- Should fallback to the provided fallback value (directory not executable)
    assert.are.equal("light", result)
  end)
end)

describe("system.get_background with command override", function()
  local system
  local plugin

  before_each(function()
    package.loaded["colorful-times.system"] = nil
    package.loaded["colorful-times"] = nil
    system = require("colorful-times.system")
    plugin = require("colorful-times")
  end)

  after_each(function()
    plugin.config.system_background_detection = nil
    package.loaded["colorful-times.system"] = nil
    package.loaded["colorful-times"] = nil
  end)

  it("returns dark when the custom command exits 0", function()
    plugin.config.system_background_detection = { "sh", "-c", "exit 0" }

    local result
    system.get_background(function(bg) result = bg end, "light")

    vim.wait(200, function() return result ~= nil end)
    assert.are.equal("dark", result)
  end)

  it("returns light when the custom command exits 1", function()
    plugin.config.system_background_detection = { "sh", "-c", "exit 1" }

    local result
    system.get_background(function(bg) result = bg end, "dark")

    vim.wait(200, function() return result ~= nil end)
    assert.are.equal("light", result)
  end)

  it("falls back when the custom command table is invalid", function()
    local orig_notify = vim.notify
    local notified = false
    plugin.config.system_background_detection = {}
    vim.notify = function()
      notified = true
    end

    local result
    system.get_background(function(bg) result = bg end, "dark")

    vim.wait(100, function() return result ~= nil end)
    vim.notify = orig_notify

    assert.is_true(notified)
    assert.are.equal("dark", result)
  end)
end)

describe("system.has_detection", function()
  local system
  local plugin
  local orig_sysname
  local orig_executable
  local orig_env

  before_each(function()
    package.loaded["colorful-times.system"] = nil
    package.loaded["colorful-times"] = nil
    system = require("colorful-times.system")
    plugin = require("colorful-times")
    orig_sysname = system.sysname
    orig_executable = vim.fn.executable
    orig_env = {
      current = vim.env.XDG_CURRENT_DESKTOP,
      session = vim.env.XDG_SESSION_DESKTOP,
    }
  end)

  after_each(function()
    system.sysname = orig_sysname
    vim.fn.executable = orig_executable
    vim.env.XDG_CURRENT_DESKTOP = orig_env.current
    vim.env.XDG_SESSION_DESKTOP = orig_env.session
    plugin.config.system_background_detection = nil
    plugin.config.system_background_detection_script = nil
    package.loaded["colorful-times.system"] = nil
    package.loaded["colorful-times"] = nil
  end)

  it("returns false when Linux auto-detection has no supported desktop backend", function()
    system.sysname = function()
      return "Linux"
    end
    vim.env.XDG_CURRENT_DESKTOP = "XFCE"
    vim.env.XDG_SESSION_DESKTOP = "XFCE"
    vim.fn.executable = function()
      return 0
    end

    assert.is_false(system.has_detection())
    assert.is_false(system.detection_info().available)
  end)
end)

describe("system.get_background unsupported platform regression", function()
  local system
  local orig_sysname

  before_each(function()
    package.loaded["colorful-times.system"] = nil
    system = require("colorful-times.system")
    orig_sysname = system.sysname
  end)

  after_each(function()
    system.sysname = orig_sysname
    package.loaded["colorful-times.system"] = nil
  end)

  it("returns the fallback for FreeBSD", function()
    system.sysname = function() return "FreeBSD" end

    local result
    system.get_background(function(bg) result = bg end, "dark")

    vim.wait(100, function() return result ~= nil end)
    assert.are.equal("dark", result)
  end)
end)
