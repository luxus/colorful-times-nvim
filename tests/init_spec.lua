describe("init lazy loading", function()
  before_each(function()
    package.loaded["colorful-times"] = nil
    package.loaded["colorful-times.core"] = nil
  end)

  after_each(function()
    package.loaded["colorful-times"] = nil
    package.loaded["colorful-times.core"] = nil
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
end)
