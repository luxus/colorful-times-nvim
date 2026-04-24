local function clear_colorful_times_modules()
  for name in pairs(package.loaded) do
    if name == "colorful-times" or name:match("^colorful%-times%.") then
      package.loaded[name] = nil
    end
  end
end

local function tui_loaded()
  for name in pairs(package.loaded) do
    if name:match("^colorful%-times%.tui") then
      return true
    end
  end
  return false
end

describe("init lazy loading", function()
  before_each(function()
    clear_colorful_times_modules()
  end)

  after_each(function()
    clear_colorful_times_modules()
  end)

  it("does not load the core module on initial require", function()
    local plugin = require("colorful-times")

    assert.is_table(plugin)
    assert.is_nil(package.loaded["colorful-times.core"])
  end)

  it("loads the core module when a lazy API is accessed", function()
    local plugin = require("colorful-times")
    local status_fn = plugin.status

    assert.is_function(status_fn)
    assert.is_not_nil(package.loaded["colorful-times.core"])
  end)

  it("does not load TUI modules until open is called", function()
    local plugin = require("colorful-times")

    assert.is_false(tui_loaded())

    local open_fn = plugin.open

    assert.is_function(open_fn)
    assert.is_not_nil(package.loaded["colorful-times.core"])
    assert.is_false(tui_loaded())
  end)
end)
