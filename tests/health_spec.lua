describe("health.check", function()
  local health_mod
  local plugin
  local state
  local system
  local orig_health
  local orig_path
  local orig_detection_info

  before_each(function()
    package.loaded["colorful-times.health"] = nil
    package.loaded["colorful-times"] = nil
    package.loaded["colorful-times.state"] = nil
    package.loaded["colorful-times.system"] = nil

    health_mod = require("colorful-times.health")
    plugin = require("colorful-times")
    state = require("colorful-times.state")
    system = require("colorful-times.system")
    orig_health = vim.health
    orig_path = state.path
    orig_detection_info = system.detection_info
  end)

  after_each(function()
    vim.health = orig_health
    state.path = orig_path
    system.detection_info = orig_detection_info
    plugin.config.schedule = {}
    package.loaded["colorful-times.health"] = nil
    package.loaded["colorful-times"] = nil
    package.loaded["colorful-times.state"] = nil
    package.loaded["colorful-times.system"] = nil
  end)

  it("reports writable state storage and an available detection backend", function()
    local events = { ok = {}, warn = {}, info = {}, error = {} }
    local tmpdir = vim.fn.tempname() .. "_health"

    state.path = function()
      return tmpdir .. "/state.json"
    end
    system.detection_info = function()
      return { available = true, detail = "custom command override" }
    end
    vim.health = {
      ok = function(msg) table.insert(events.ok, msg) end,
      warn = function(msg) table.insert(events.warn, msg) end,
      info = function(msg) table.insert(events.info, msg) end,
      error = function(msg) table.insert(events.error, msg) end,
    }

    plugin.config.schedule = {}
    health_mod.check()

    vim.fn.delete(tmpdir, "rf")

    assert.is_true(vim.iter(events.ok):any(function(msg)
      return msg:match("State directory writable")
    end))
    assert.is_true(vim.iter(events.ok):any(function(msg)
      return msg:match("System detection available")
    end))
  end)

  it("warns about unavailable detection backends and invalid schedules", function()
    local events = { ok = {}, warn = {}, info = {}, error = {} }
    local tmpdir = vim.fn.tempname() .. "_health"

    state.path = function()
      return tmpdir .. "/state.json"
    end
    system.detection_info = function()
      return { available = false, detail = "no supported Linux desktop detected" }
    end
    vim.health = {
      ok = function(msg) table.insert(events.ok, msg) end,
      warn = function(msg) table.insert(events.warn, msg) end,
      info = function(msg) table.insert(events.info, msg) end,
      error = function(msg) table.insert(events.error, msg) end,
    }

    plugin.config.schedule = {
      { start = "bad", stop = "18:00", colorscheme = "broken" },
    }
    health_mod.check()

    vim.fn.delete(tmpdir, "rf")

    assert.is_true(vim.iter(events.warn):any(function(msg)
      return msg:match("System detection unavailable")
    end))
    assert.is_true(vim.iter(events.warn):any(function(msg)
      return msg:match("Schedule entry 1 is invalid")
    end))
  end)
end)
