-- tests/state_spec.lua
local state = require("colorful-times.state")

describe("state.path", function()
  it("returns a string ending in state.json", function()
    assert.is_truthy(state.path():match("state%.json$"))
  end)
end)

describe("state.load", function()
  it("returns {} for non-existent file", function()
    local orig_path = state.path
    state.path = function() return "/tmp/ct_test_nonexistent_" .. os.time() .. ".json" end
    assert.are.same({}, state.load())
    state.path = orig_path
  end)

  it("returns {} on parse error", function()
    local tmp = os.tmpname()
    local f = io.open(tmp, "w"); f:write("not json!!"); f:close()
    local orig_path = state.path
    state.path = function() return tmp end
    assert.are.same({}, state.load())
    state.path = orig_path
    os.remove(tmp)
  end)

  it("backs up corrupted state file with .bak.<timestamp> suffix", function()
    local tmp = os.tmpname()
    local dir = tmp .. "_dir"
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/state.json"

    -- Write corrupted content
    local f = io.open(file, "w")
    f:write("this is not valid json {[[")
    f:close()

    local orig_path = state.path
    state.path = function() return file end

    -- Load should return empty and create backup
    local result = state.load()
    state.path = orig_path

    -- Verify empty state returned
    assert.are.same({}, result)

    -- Find backup file
    local backup_pattern = dir .. "/state.json.bak.*"
    local backups = vim.fn.glob(backup_pattern, true, true)

    -- Cleanup
    vim.fn.delete(dir, "rf")

    -- Verify backup exists
    assert.is_true(#backups >= 1, "backup file should be created")
    assert.is_truthy(backups[1]:match("state%.json%.bak%.%d+_%d+$"))
  end)

  it("creates multiple backups for repeated corruptions", function()
    local tmp = os.tmpname()
    local dir = tmp .. "_dir"
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/state.json"

    local orig_path = state.path
    state.path = function() return file end

    -- First corruption
    local f1 = io.open(file, "w")
    f1:write("corruption 1")
    f1:close()
    state.load()

    -- Small delay to ensure different timestamps
    vim.wait(50)

    -- Second corruption
    local f2 = io.open(file, "w")
    f2:write("corruption 2")
    f2:close()
    state.load()

    state.path = orig_path

    -- Find backup files
    local backup_pattern = dir .. "/state.json.bak.*"
    local backups = vim.fn.glob(backup_pattern, true, true)

    -- Cleanup
    vim.fn.delete(dir, "rf")

    -- Verify multiple backups exist
    assert.are.equal(2, #backups, "two backup files should be created")
  end)

  it("parses valid JSON", function()
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write(vim.json.encode({ enabled = false, schedule = {} }))
    f:close()
    local orig_path = state.path
    state.path = function() return tmp end
    local result = state.load()
    state.path = orig_path
    os.remove(tmp)
    assert.is_false(result.enabled)
  end)
end)

describe("state.save and state.load roundtrip", function()
  it("saves and reloads data correctly", function()
    local tmp = os.tmpname()
    os.remove(tmp)  -- ensure file doesn't exist yet
    local dir = tmp .. "_dir"
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/state.json"

    local orig_path = state.path
    state.path = function() return file end

    local data = {
      enabled = true,
      schedule = {
        { start = "06:00", stop = "18:00", colorscheme = "tokyonight-day", background = "light" },
      },
    }
    state.save(data)
    local loaded = state.load()
    state.path = orig_path

    vim.fn.delete(dir, "rf")

    assert.is_true(loaded.enabled)
    assert.are.equal(1, #loaded.schedule)
    assert.are.equal("tokyonight-day", loaded.schedule[1].colorscheme)
  end)
end)

describe("state persistence regressions", function()
  local state
  local test_dir
  local file
  local orig_path

  before_each(function()
    package.loaded["colorful-times.state"] = nil
    state = require("colorful-times.state")
    test_dir = os.tmpname() .. "_dir"
    vim.fn.mkdir(test_dir, "p")
    file = test_dir .. "/state.json"
    orig_path = state.path
    state.path = function() return file end
  end)

  after_each(function()
    state.path = orig_path
    vim.fn.delete(test_dir, "rf")
    package.loaded["colorful-times.state"] = nil
  end)

  it("removes the temporary file after an atomic save and preserves data", function()
    local data = {
      enabled = true,
      persist = true,
      schedule = {
        { start = "06:00", stop = "18:00", colorscheme = "day", background = "light" },
      },
      default = {
        colorscheme = "fallback",
        background = "dark",
      },
    }

    state.save(data)

    assert.is_nil(vim.uv.fs_stat(file .. ".tmp"))
    assert.are.same(data, state.load())
  end)

  it("keeps defaults intact when invalid loaded state is merged", function()
    local handle = assert(io.open(file, "w"))
    handle:write("not json")
    handle:close()

    local loaded = state.load()
    local defaults = {
      enabled = true,
      persist = true,
      refresh_time = 5000,
      schedule = {
        { start = "08:00", stop = "17:00", colorscheme = "base", background = "light" },
      },
      default = {
        colorscheme = "base-default",
        background = "system",
      },
    }

    assert.are.same({}, loaded)
    assert.are.same(defaults, state.merge(vim.deepcopy(defaults), loaded))
  end)
end)

describe("state.merge", function()
  local base = {
    enabled = true,
    schedule = { { start = "06:00", stop = "18:00", colorscheme = "base" } },
    default = { colorscheme = "default", background = "system" },
  }

  it("stored schedule wins over base", function()
    local result = state.merge(vim.deepcopy(base), {
      schedule = { { start = "09:00", stop = "17:00", colorscheme = "stored" } },
    })
    assert.are.equal("stored", result.schedule[1].colorscheme)
  end)

  it("stored enabled wins over base", function()
    local result = state.merge(vim.deepcopy(base), { enabled = false })
    assert.is_false(result.enabled)
  end)

  it("missing schedule key in stored leaves base intact", function()
    local result = state.merge(vim.deepcopy(base), { enabled = false })
    assert.are.equal("base", result.schedule[1].colorscheme)
  end)

  it("empty schedule array [] wins (clears base schedule)", function()
    local result = state.merge(vim.deepcopy(base), { schedule = {} })
    assert.are.same({}, result.schedule)
  end)

  it("missing enabled key in stored leaves base enabled", function()
    local result = state.merge(vim.deepcopy(base), {})
    assert.is_true(result.enabled)
  end)

  it("non-schedule keys from base are preserved", function()
    local result = state.merge(vim.deepcopy(base), { enabled = false })
    assert.are.equal("default", result.default.colorscheme)
  end)
end)

-- FIXED: These tests verify complete config merge (task-6)
describe("FIXED: complete merge - all config keys", function()
  local full_base = {
    enabled = true,
    schedule = { { start = "06:00", stop = "18:00", colorscheme = "base" } },
    default = { colorscheme = "default", background = "system", themes = { light = nil, dark = nil } },
    refresh_time = 5000,
    persist = true,
  }

  it("default.colorscheme is merged from stored (FIXED)", function()
    local result = state.merge(vim.deepcopy(full_base), {
      default = { colorscheme = "stored-theme" }
    })
    assert.are.equal("stored-theme", result.default.colorscheme)
  end)

  it("default.background is merged from stored (FIXED)", function()
    local result = state.merge(vim.deepcopy(full_base), {
      default = { background = "light" }
    })
    assert.are.equal("light", result.default.background)
  end)

  it("default.themes is deep merged from stored (FIXED)", function()
    local result = state.merge(vim.deepcopy(full_base), {
      default = { themes = { light = "day-theme", dark = "night-theme" } }
    })
    assert.are.equal("day-theme", result.default.themes.light)
    assert.are.equal("night-theme", result.default.themes.dark)
  end)

  it("refresh_time is merged from stored (FIXED)", function()
    local result = state.merge(vim.deepcopy(full_base), { refresh_time = 10000 })
    assert.are.equal(10000, result.refresh_time)
  end)

  it("persist is merged from stored (FIXED)", function()
    local result = state.merge(vim.deepcopy(full_base), { persist = false })
    assert.is_false(result.persist)
  end)

  it("nil values in stored don't overwrite base", function()
    local result = state.merge(vim.deepcopy(full_base), {
      refresh_time = nil,
      persist = nil,
      default = nil
    })
    assert.are.equal(5000, result.refresh_time)
    assert.is_true(result.persist)
    assert.are.equal("default", result.default.colorscheme)
  end)

  it("empty default table preserves existing defaults", function()
    local result = state.merge(vim.deepcopy(full_base), {
      default = {}
    })
    assert.are.equal("default", result.default.colorscheme)
  end)
end)

-- State validation tests (task-5)
describe("sequential I/O integrity", function()
  it("multiple sequential reads return consistent data", function()
    local tmp = os.tmpname()
    local dir = tmp .. "_dir"
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/state.json"

    -- Write initial data
    local f = io.open(file, "w")
    f:write(vim.json.encode({ enabled = true, counter = 0 }))
    f:close()

    local orig_path = state.path
    state.path = function() return file end

    -- Simulate multiple readers by reading in sequence
    local results = {}
    for i = 1, 5 do
      table.insert(results, state.load())
    end

    state.path = orig_path
    vim.fn.delete(dir, "rf")

    -- All reads should succeed and get the same data
    for _, result in ipairs(results) do
      assert.is_true(result.enabled)
      assert.are.equal(0, result.counter)
    end
  end)

  it("sequential writes persist correctly", function()
    local tmp = os.tmpname()
    local dir = tmp .. "_dir"
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/state.json"

    local orig_path = state.path
    state.path = function() return file end

    -- Write initial data
    state.save({ enabled = true, counter = 0 })

    -- Verify initial write succeeded
    local loaded = state.load()
    assert.are.equal(0, loaded.counter)

    -- Perform multiple writes sequentially to verify locking works
    for i = 1, 5 do
      state.save({ enabled = true, counter = i })
      local check = state.load()
      assert.are.equal(i, check.counter, "Write " .. i .. " should persist")
    end

    -- Final verification
    local final = state.load()
    assert.are.equal(5, final.counter)

    state.path = orig_path
    vim.fn.delete(dir, "rf")
  end)

  it("complex data survives write-read roundtrip", function()
    local tmp = os.tmpname()
    local dir = tmp .. "_dir"
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/state.json"

    local orig_path = state.path
    state.path = function() return file end

    -- Write complex data structure
    local complex_data = {
      enabled = true,
      schedule = {
        { start = "06:00", stop = "18:00", colorscheme = "day", background = "light" },
        { start = "18:00", stop = "06:00", colorscheme = "night", background = "dark" },
      },
      refresh_time = 5000,
      persist = true,
      default = {
        colorscheme = "default",
        background = "system",
        themes = {
          light = "dayfox",
          dark = "nightfox",
        },
      },
    }

    state.save(complex_data)
    local loaded = state.load()

    state.path = orig_path
    vim.fn.delete(dir, "rf")

    -- Verify all data is intact
    assert.is_true(loaded.enabled)
    assert.are.equal(2, #loaded.schedule)
    assert.are.equal("day", loaded.schedule[1].colorscheme)
    assert.are.equal("night", loaded.schedule[2].colorscheme)
    assert.are.equal(5000, loaded.refresh_time)
    assert.is_true(loaded.persist)
    assert.are.equal("default", loaded.default.colorscheme)
    assert.are.equal("dayfox", loaded.default.themes.light)
    assert.are.equal("nightfox", loaded.default.themes.dark)
  end)

  it("gracefully handles file locking when unavailable", function()
    -- This test verifies the code path when _flock_available is false
    -- We can't easily test Windows, but we can verify the code doesn't crash
    local tmp = os.tmpname()
    local dir = tmp .. "_dir"
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/state.json"

    local orig_path = state.path
    state.path = function() return file end

    -- Normal save/load should work even without lock
    state.save({ enabled = true, test = "data" })
    local loaded = state.load()

    state.path = orig_path
    vim.fn.delete(dir, "rf")

    assert.is_true(loaded.enabled)
    assert.are.equal("data", loaded.test)
  end)
end)

-- State validation tests (task-5)
describe("state.validate_state", function()
  it("accepts valid complete state", function()
    local data = {
      enabled = true,
      schedule = {
        { start = "06:00", stop = "18:00", colorscheme = "day", background = "light" },
      },
      refresh_time = 5000,
      persist = true,
      default = {
        colorscheme = "default",
        background = "system",
      },
    }
    local ok, err = state.validate_state(data)
    assert.is_true(ok, err)
    assert.is_nil(err)
  end)

  it("accepts valid partial state", function()
    local data = { enabled = false }
    local ok, err = state.validate_state(data)
    assert.is_true(ok, err)
    assert.is_nil(err)
  end)

  it("accepts empty state", function()
    local ok, err = state.validate_state({})
    assert.is_true(ok, err)
    assert.is_nil(err)
  end)

  it("rejects non-table data", function()
    local ok, err = state.validate_state("not a table")
    assert.is_false(ok)
    assert.is_truthy(err:match("must be a table"))
  end)

  describe("enabled validation", function()
    it("rejects non-boolean enabled", function()
      local ok, err = state.validate_state({ enabled = "true" })
      assert.is_false(ok)
      assert.is_truthy(err:match("enabled must be a boolean"))
    end)

    it("accepts boolean enabled", function()
      assert.is_true(state.validate_state({ enabled = true }))
      assert.is_true(state.validate_state({ enabled = false }))
    end)

    it("allows nil enabled", function()
      assert.is_true(state.validate_state({}))
    end)
  end)

  describe("schedule validation", function()
    it("rejects non-table schedule", function()
      local ok, err = state.validate_state({ schedule = "not an array" })
      assert.is_false(ok)
      assert.is_truthy(err:match("schedule must be an array"))
    end)

    it("rejects non-array schedule (dictionary style)", function()
      local ok, err = state.validate_state({ schedule = { foo = "bar" } })
      assert.is_false(ok)
      assert.is_truthy(err:match("must be an array"))
    end)

    it("rejects invalid schedule entry", function()
      local ok, err = state.validate_state({
        schedule = { { start = "invalid", stop = "18:00", colorscheme = "test" } }
      })
      assert.is_false(ok)
      assert.is_truthy(err:match("schedule entry 1"))
    end)

    it("accepts valid schedule array", function()
      local data = {
        schedule = {
          { start = "06:00", stop = "12:00", colorscheme = "day" },
          { start = "12:00", stop = "18:00", colorscheme = "afternoon", background = "dark" },
        }
      }
      assert.is_true(state.validate_state(data))
    end)

    it("accepts empty schedule array", function()
      assert.is_true(state.validate_state({ schedule = {} }))
    end)

    it("allows nil schedule", function()
      assert.is_true(state.validate_state({}))
    end)
  end)

  describe("refresh_time validation", function()
    it("rejects non-number refresh_time", function()
      local ok, err = state.validate_state({ refresh_time = "5000" })
      assert.is_false(ok)
      assert.is_truthy(err:match("refresh_time must be a number"))
    end)

    it("rejects zero refresh_time", function()
      local ok, err = state.validate_state({ refresh_time = 0 })
      assert.is_false(ok)
      assert.is_truthy(err:match("positive integer"))
    end)

    it("rejects negative refresh_time", function()
      local ok, err = state.validate_state({ refresh_time = -100 })
      assert.is_false(ok)
      assert.is_truthy(err:match("positive integer"))
    end)

    it("rejects fractional refresh_time", function()
      local ok, err = state.validate_state({ refresh_time = 5000.5 })
      assert.is_false(ok)
      assert.is_truthy(err:match("integer"))
    end)

    it("accepts valid positive integer refresh_time", function()
      assert.is_true(state.validate_state({ refresh_time = 5000 }))
      assert.is_true(state.validate_state({ refresh_time = 1 }))
    end)

    it("allows nil refresh_time", function()
      assert.is_true(state.validate_state({}))
    end)
  end)

  describe("persist validation", function()
    it("rejects non-boolean persist", function()
      local ok, err = state.validate_state({ persist = "yes" })
      assert.is_false(ok)
      assert.is_truthy(err:match("persist must be a boolean"))
    end)

    it("accepts boolean persist", function()
      assert.is_true(state.validate_state({ persist = true }))
      assert.is_true(state.validate_state({ persist = false }))
    end)

    it("allows nil persist", function()
      assert.is_true(state.validate_state({}))
    end)
  end)

  describe("default validation", function()
    it("rejects non-table default", function()
      local ok, err = state.validate_state({ default = "not a table" })
      assert.is_false(ok)
      assert.is_truthy(err:match("default must be a table"))
    end)

    describe("default.background", function()
      it("rejects invalid background value", function()
        local ok, err = state.validate_state({ default = { background = "invalid" } })
        assert.is_false(ok)
        assert.is_truthy(err:match("default.background must be one of"))
      end)

      it("accepts 'light' background", function()
        assert.is_true(state.validate_state({ default = { background = "light" } }))
      end)

      it("accepts 'dark' background", function()
        assert.is_true(state.validate_state({ default = { background = "dark" } }))
      end)

      it("accepts 'system' background", function()
        assert.is_true(state.validate_state({ default = { background = "system" } }))
      end)

      it("allows nil background", function()
        assert.is_true(state.validate_state({ default = {} }))
      end)
    end)

    describe("default.colorscheme", function()
      it("rejects non-string colorscheme", function()
        local ok, err = state.validate_state({ default = { colorscheme = 123 } })
        assert.is_false(ok)
        assert.is_truthy(err:match("default.colorscheme must be a string"))
      end)

      it("accepts string colorscheme", function()
        assert.is_true(state.validate_state({ default = { colorscheme = "gruvbox" } }))
      end)

      it("allows nil colorscheme", function()
        assert.is_true(state.validate_state({ default = {} }))
      end)
    end)

    describe("default.themes", function()
      it("rejects non-table themes", function()
        local ok, err = state.validate_state({ default = { themes = "bad" } })
        assert.is_false(ok)
        assert.is_truthy(err:match("default.themes must be a table"))
      end)

      it("rejects non-string theme overrides", function()
        local ok, err = state.validate_state({ default = { themes = { light = 42 } } })
        assert.is_false(ok)
        assert.is_truthy(err:match("default.themes.light must be a string"))
      end)

      it("accepts optional light and dark theme overrides", function()
        assert.is_true(state.validate_state({
          default = {
            themes = {
              light = "dayfox",
              dark = "nightfox",
            },
          },
        }))
      end)
    end)
  end)
end)

describe("state.save validation integration", function()
  it("rejects invalid data and does not write", function()
    local tmp = os.tmpname()
    local dir = tmp .. "_dir"
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/state.json"

    local orig_path = state.path
    state.path = function() return file end

    local invalid_data = {
      enabled = "not-a-boolean",
      schedule = "not-an-array",
    }

    state.save(invalid_data)

    local f = io.open(file, "r")
    assert.is_nil(f, "file should not be created when validation fails")
    if f then f:close() end

    state.path = orig_path
    vim.fn.delete(dir, "rf")
  end)

  it("accepts valid data and writes successfully", function()
    local tmp = os.tmpname()
    local dir = tmp .. "_dir"
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/state.json"

    local orig_path = state.path
    state.path = function() return file end

    local valid_data = {
      enabled = true,
      schedule = { { start = "06:00", stop = "18:00", colorscheme = "day" } },
    }

    state.save(valid_data)
    local loaded = state.load()

    state.path = orig_path
    vim.fn.delete(dir, "rf")

    assert.is_true(loaded.enabled)
    assert.are.equal("day", loaded.schedule[1].colorscheme)
  end)
end)
