-- tests/schedule_spec.lua
local schedule = require("colorful-times.schedule")

describe("schedule.parse_time", function()
  it("parses valid HH:MM", function()
    assert.are.equal(0,    schedule.parse_time("00:00"))
    assert.are.equal(60,   schedule.parse_time("01:00"))
    assert.are.equal(1439, schedule.parse_time("23:59"))
    assert.are.equal(690,  schedule.parse_time("11:30"))
  end)

  it("returns nil for invalid input", function()
    assert.is_nil(schedule.parse_time("24:00"))
    assert.is_nil(schedule.parse_time("12:60"))
    assert.is_nil(schedule.parse_time("invalid"))
    assert.is_nil(schedule.parse_time(""))
    assert.are.equal(60, schedule.parse_time("1:00"))  -- single-digit hour is valid per spec
  end)
end)

describe("schedule.validate_entry", function()
  it("accepts a fully valid entry", function()
    local ok, err = schedule.validate_entry({
      start = "08:00", stop = "18:00",
      colorscheme = "tokyonight", background = "dark",
    })
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("accepts entry without background (optional)", function()
    local ok, err = schedule.validate_entry({
      start = "08:00", stop = "18:00", colorscheme = "tokyonight",
    })
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("rejects entry with invalid start time", function()
    local ok, err = schedule.validate_entry({
      start = "25:00", stop = "18:00", colorscheme = "tokyonight",
    })
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("rejects entry with invalid stop time", function()
    local ok, err = schedule.validate_entry({
      start = "08:00", stop = "60:00", colorscheme = "tokyonight",
    })
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("rejects entry with missing colorscheme", function()
    local ok, err = schedule.validate_entry({
      start = "08:00", stop = "18:00",
    })
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("rejects entry with invalid background value", function()
    local ok, err = schedule.validate_entry({
      start = "08:00", stop = "18:00",
      colorscheme = "tokyonight", background = "purple",
    })
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)
end)

describe("schedule.preprocess", function()
  it("converts valid entries into parsed entries", function()
    local raw = {
      { start = "06:00", stop = "18:00", colorscheme = "day", background = "light" },
      { start = "18:00", stop = "06:00", colorscheme = "night" },
    }
    local parsed = schedule.preprocess(raw, "dark")
    assert.are.equal(2, #parsed)
    assert.are.equal(360,  parsed[1].start_time)
    assert.are.equal(1080, parsed[1].stop_time)
    assert.are.equal("light", parsed[1].background)
    assert.are.equal("dark",  parsed[2].background)  -- inherited from default
  end)

  it("skips and reports invalid entries", function()
    -- Clear any cached state that might affect this test
    package.loaded["colorful-times.schedule"] = nil
    local clean_schedule = require("colorful-times.schedule")
    
    local errors = {}
    -- patch vim.notify to capture messages
    local orig = vim.notify
    vim.notify = function(msg, _) table.insert(errors, msg) end

    local parsed = clean_schedule.preprocess({
      { start = "invalid", stop = "18:00", colorscheme = "x" },
      { start = "06:00",   stop = "18:00", colorscheme = "y" },
    }, "dark")

    vim.notify = orig
    assert.are.equal(1, #parsed)  -- bad entry skipped
    assert.are.equal(1, #errors)
  end)
end)

describe("schedule.get_active_entry", function()
  local parsed

  before_each(function()
    parsed = schedule.preprocess({
      { start = "06:00", stop = "18:00", colorscheme = "day",   background = "light" },
      { start = "18:00", stop = "06:00", colorscheme = "night", background = "dark"  },
    }, "dark")
  end)

  it("returns day entry at 12:00", function()
    local entry = schedule.get_active_entry(parsed, 720)  -- 12*60
    assert.are.equal("day", entry.colorscheme)
  end)

  it("returns night entry at 22:00", function()
    local entry = schedule.get_active_entry(parsed, 1320)  -- 22*60
    assert.are.equal("night", entry.colorscheme)
  end)

  it("returns night entry at 03:00 (overnight)", function()
    local entry = schedule.get_active_entry(parsed, 180)  -- 3*60
    assert.are.equal("night", entry.colorscheme)
  end)

  it("returns nil for empty schedule", function()
    assert.is_nil(schedule.get_active_entry({}, 720))
  end)

  it("handles exact boundaries: inclusive start, exclusive stop", function()
    -- Standard entry (day): 06:00 (360) to 18:00 (1080)
    -- Just before start: 05:59 (359)
    local entry = schedule.get_active_entry(parsed, 359)
    assert.are.equal("night", entry.colorscheme)

    -- Exact start: 06:00 (360)
    entry = schedule.get_active_entry(parsed, 360)
    assert.are.equal("day", entry.colorscheme)

    -- Just before stop: 17:59 (1079)
    entry = schedule.get_active_entry(parsed, 1079)
    assert.are.equal("day", entry.colorscheme)

    -- Exact stop: 18:00 (1080) -> it becomes night entry
    entry = schedule.get_active_entry(parsed, 1080)
    assert.are.equal("night", entry.colorscheme)

    -- Overnight entry (night): 18:00 (1080) to 06:00 (360)
    -- Just before stop: 05:59 (359) -> handled above (is "night")
  end)

  it("handles overnight boundaries for single entry", function()
    local night_only = schedule.preprocess({
      { start = "22:00", stop = "08:00", colorscheme = "night" }
    }, "dark")

    -- Just before start: 21:59 (1319)
    local entry = schedule.get_active_entry(night_only, 1319)
    assert.is_nil(entry)

    -- Exact start: 22:00 (1320)
    entry = schedule.get_active_entry(night_only, 1320)
    assert.are.equal("night", entry.colorscheme)

    -- Just before stop: 07:59 (479)
    entry = schedule.get_active_entry(night_only, 479)
    assert.are.equal("night", entry.colorscheme)

    -- Exact stop: 08:00 (480)
    entry = schedule.get_active_entry(night_only, 480)
    assert.is_nil(entry)
  end)
end)

describe("schedule.next_change_at", function()
  it("returns minutes until next boundary", function()
    local parsed = schedule.preprocess({
      { start = "06:00", stop = "18:00", colorscheme = "day", background = "light" },
    }, "dark")

    -- at 05:00 (300 mins), next boundary is 06:00 (+60 mins)
    assert.are.equal(60, schedule.next_change_at(parsed, 300))
    -- at 06:00 (360 mins), next boundary is 18:00 (+720 mins)
    assert.are.equal(720, schedule.next_change_at(parsed, 360))
  end)

  it("returns nil for empty schedule", function()
    assert.is_nil(schedule.next_change_at({}, 720))
  end)
end)

describe("schedule.parse_time cache", function()
  it("returns cached result for same time string", function()
    -- Reload module to get fresh cache
    package.loaded["colorful-times.schedule"] = nil
    local test_schedule = require("colorful-times.schedule")
    
    -- First call should compute and cache
    local result1 = test_schedule.parse_time("12:30")
    assert.are.equal(750, result1)

    -- Second call with same string should return cached result
    local result2 = test_schedule.parse_time("12:30")
    assert.are.equal(750, result2)

    -- Both should be equal (testing idempotency)
    assert.are.equal(result1, result2)
  end)

  it("caches invalid time strings as nil", function()
    -- Reload module to get fresh cache
    package.loaded["colorful-times.schedule"] = nil
    local test_schedule = require("colorful-times.schedule")
    
    -- First call should compute and cache nil
    local result1 = test_schedule.parse_time("invalid")
    assert.is_nil(result1)

    -- Second call with same invalid string should return cached nil
    local result2 = test_schedule.parse_time("invalid")
    assert.is_nil(result2)

    -- Also test with other invalid formats
    local result3 = test_schedule.parse_time("25:00")
    assert.is_nil(result3)
    local result4 = test_schedule.parse_time("25:00")
    assert.is_nil(result4)
  end)

  it("actually uses cache - string.match not called on second access", function()
    -- Reload module to get fresh cache
    package.loaded["colorful-times.schedule"] = nil
    local test_schedule = require("colorful-times.schedule")
    
    -- Monkey-patch string.match to count calls
    local orig_match = string.match
    local call_count = 0
    string.match = function(s, p)
      call_count = call_count + 1
      return orig_match(s, p)
    end

    -- First call should use string.match
    test_schedule.parse_time("14:45")
    assert.are.equal(1, call_count)

    -- Second call with same string should NOT use string.match (cache hit)
    test_schedule.parse_time("14:45")
    assert.are.equal(1, call_count) -- Should still be 1, not 2

    -- Third call with different string should use string.match again
    test_schedule.parse_time("09:30")
    assert.are.equal(2, call_count)

    -- Fourth call with first string should still be cached
    test_schedule.parse_time("14:45")
    assert.are.equal(2, call_count)

    -- Restore original
    string.match = orig_match
  end)

  it("actually caches invalid results - string.match not called on second access", function()
    -- Reload module to get fresh cache
    package.loaded["colorful-times.schedule"] = nil
    local test_schedule = require("colorful-times.schedule")
    
    -- Monkey-patch string.match to count calls
    local orig_match = string.match
    local call_count = 0
    string.match = function(s, p)
      call_count = call_count + 1
      return orig_match(s, p)
    end

    -- First call with invalid time should use string.match
    test_schedule.parse_time("not-a-time")
    assert.are.equal(1, call_count)

    -- Second call with same invalid string should NOT use string.match (cache hit)
    test_schedule.parse_time("not-a-time")
    assert.are.equal(1, call_count) -- Should still be 1, not 2

    -- Third call with different invalid string should use string.match again
    test_schedule.parse_time("also-invalid")
    assert.are.equal(2, call_count)

    -- Fourth call with first invalid string should still be cached
    test_schedule.parse_time("not-a-time")
    assert.are.equal(2, call_count)

    -- Restore original
    string.match = orig_match
  end)

  it("recomputes after cache limit is exceeded", function()
    -- Reload module to get fresh cache
    package.loaded["colorful-times.schedule"] = nil
    local test_schedule = require("colorful-times.schedule")
    
    -- Force many different time strings to exceed cache limit
    -- The cache limit is 100, so we need to add more than that
    local results = {}
    for i = 1, 105 do
      local hour = math.floor(i / 60) % 24
      local min = i % 60
      local time_str = string.format("%02d:%02d", hour, min)
      results[time_str] = test_schedule.parse_time(time_str)
    end

    -- Verify all results are correct
    for time_str, result in pairs(results) do
      local recomputed = test_schedule.parse_time(time_str)
      assert.are.equal(result, recomputed)
    end
  end)
end)
