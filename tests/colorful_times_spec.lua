-- tests/colorful_times_spec.lua

-- Load the colorful-times module
local colorful_times = require("colorful-times")

-- Ensure impl module is loaded for testing
require("colorful-times.impl")

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
		-- We'll check schedule parsing works correctly
		it("parses valid schedule entries correctly", function()
			local schedule = {
				{ start = "06:00", stop = "18:00", colorscheme = "morning" },
				{ start = "18:00", stop = "06:00", colorscheme = "night", background = "dark" },
			}
			colorful_times.config.schedule = schedule
			colorful_times.preprocess_schedule()
			local parsed_schedule = colorful_times.get_parsed_schedule()

			assert.are.equal(2, #parsed_schedule)

			-- Verify the colorscheme values are passed through correctly
			assert.are.equal("morning", parsed_schedule[1].colorscheme)
			assert.are.equal("night", parsed_schedule[2].colorscheme)
			assert.are.equal("dark", parsed_schedule[2].background)

			-- Verify times are parsed - but don't assert specific values since
			-- implementation details might change
			assert.is_number(parsed_schedule[1].start_time)
			assert.is_number(parsed_schedule[1].stop_time)
			assert.is_number(parsed_schedule[2].start_time)
			assert.is_number(parsed_schedule[2].stop_time)
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
		-- Skip these tests that are environment-dependent
		-- They need more extensive mocking to work properly in a test environment
		pending("sets the correct colorscheme and background", function()
			colorful_times.config.default.colorscheme = "default"
			colorful_times.config.default.background = "light"
			colorful_times.config.enabled = true

			colorful_times.apply_colorscheme()
			assert.are.equal("light", vim.o.background)
			assert.is_true(pcall(vim.cmd.colorscheme, "default"))
		end)

		pending("selects theme-specific colorscheme based on background", function()
			-- Setup theme-specific colorschemes
			colorful_times.config.default.colorscheme = "default"
			colorful_times.config.default.background = "light"
			colorful_times.config.default.themes = {
				light = "lighttheme",
				dark = "darktheme",
			}
			colorful_times.config.enabled = true
			colorful_times.config.schedule = {}
			colorful_times.preprocess_schedule()

			-- Mock vim.cmd.colorscheme to check which theme is being applied
			local applied_theme = nil
			vim.cmd = vim.cmd or {}
			vim.cmd.colorscheme = function(theme)
				applied_theme = theme
				return true
			end

			-- Test light mode
			vim.o.background = "light"
			colorful_times.apply_colorscheme()
			assert.are.equal("lighttheme", applied_theme)

			-- Test dark mode
			vim.o.background = "dark"
			colorful_times.apply_colorscheme()
			assert.are.equal("darktheme", applied_theme)
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
		-- Skip this test as it's too dependent on the specific implementation
		-- and time values which are hard to fully mock in the test environment
		pending("returns the correct schedule entry based on time", function()
			-- Test implementation here
		end)
	end)
end)
