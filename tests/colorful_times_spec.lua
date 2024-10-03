-- tests/colorful_times_spec.lua

local colorful_times = require("colorful-times")

describe("ColorfulTimes Plugin", function()
  -- Test for parsing time strings into minutes since midnight
  describe("parse_time", function()
    it("parses valid time strings correctly", function()
      assert.are.equal(60, colorful_times.parse_time("01:00"))
      assert.are.equal(0, colorful_times.parse_time("00:00"))
      assert.are.equal(1439, colorful_times.parse_time("23:59"))
    end)

    it("returns nil for invalid time strings", function()
      assert.is_nil(colorful_times.parse_time("24:00"))
      assert.is_nil(colorful_times.parse_time("12:60"))
      assert.is_nil(colorful_times.parse_time("invalid"))
    end)
  end)

  -- Test for handling schedule pre-processing
  describe("preprocess_schedule", function()
    it("parses valid schedule entries correctly", function()
      local schedule = {
        { start = "06:00", stop = "18:00", colorscheme = "morning" },
        { start = "18:00", stop = "06:00", colorscheme = "night",  background = "dark" },
      }
      colorful_times.config.schedule = schedule
      colorful_times.preprocess_schedule()
      local parsed_schedule = colorful_times.get_parsed_schedule()

      assert.are.equal(2, #parsed_schedule)
      assert.are.equal(360, parsed_schedule[1].start_time)    -- 06:00 AM
      assert.are.equal(1080, parsed_schedule[1].stop_time)    -- 06:00 PM
      assert.are.equal(1080, parsed_schedule[2].start_time)   -- 06:00 PM
      assert.are.equal(360 + 1440, parsed_schedule[2].stop_time) -- 06:00 AM next day
    end)
  end)

  -- Test for system background detection callback handling
  describe("get_system_background", function()
    it("calls the callback with the correct background value", function()
      local function callback(bg)
        assert.is_true(bg == "dark" or bg == "light")
      end

      colorful_times.get_system_background(callback, "dark")
    end)
  end)

  -- Test for applying colorscheme
  describe("apply_colorscheme", function()
    it("sets the correct colorscheme and background", function()
      colorful_times.config.default.colorscheme = "default"
      colorful_times.config.default.background = "light"
      colorful_times.config.enabled = true

      colorful_times.apply_colorscheme()
      assert.are.equal("light", vim.o.background)
      assert.is_true(pcall(vim.cmd.colorscheme, "default"))
    end)
  end)

  -- Test for handling the enabled/disabled state
  describe("toggle", function()
    it("toggles the enabled state correctly", function()
      colorful_times.toggle()
      assert.is_false(colorful_times.config.enabled)
      colorful_times.toggle()
      assert.is_true(colorful_times.config.enabled)
    end)
  end)

  -- Test to verify schedule-based colorscheme changes
  describe("get_active_colorscheme", function()
    it("selects the correct colorscheme based on schedule", function()
      local schedule = {
        { start = "00:00", stop = "12:00", colorscheme = "morning" },
        { start = "12:00", stop = "23:59", colorscheme = "afternoon" },
      }
      colorful_times.config.schedule = schedule
      colorful_times.preprocess_schedule()

      vim.fn = vim.fn or {}
      vim.fn.strftime = function()
        return "10:00"
      end -- Mock current time

      local active_scheme = colorful_times.get_active_colorscheme()
      assert.are.equal("morning", active_scheme.colorscheme)
    end)
  end)
end)
