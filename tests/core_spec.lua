local M = require("colorful-times")
local core = require("colorful-times.core")
local state = require("colorful-times.state")

describe("core module loading", function()
	it("loads without error", function()
		assert.has_no.errors(function()
			require("colorful-times.core")
		end)
	end)
end)

describe("core.setup", function()
	local original_config
	local original_state_load
	local original_state_merge
	local original_apply_colorscheme

	before_each(function()
		original_config = vim.deepcopy(M.config)
		original_state_load = state.load
		original_state_merge = state.merge
		original_apply_colorscheme = core.apply_colorscheme

		-- Mock out side-effects
		state.load = function()
			return {}
		end
		core.apply_colorscheme = function() end
	end)

	after_each(function()
		M.config = original_config
		state.load = original_state_load
		state.merge = original_state_merge
		core.apply_colorscheme = original_apply_colorscheme
	end)

	it("handles nil opts without error", function()
		assert.has_no.errors(function()
			core.setup(nil)
		end)
	end)

	it("performs shallow merge for primitive top-level config values", function()
		core.setup({
			enabled = false,
			refresh_time = 9999,
		})

		assert.is_false(M.config.enabled)
		assert.are.equal(9999, M.config.refresh_time)
	end)

	it("performs deep merge for nested default table", function()
		core.setup({
			default = {
				background = "light",
				themes = {
					light = "my_light_theme",
				},
			},
		})

		assert.are.equal("light", M.config.default.background)
		assert.are.equal("my_light_theme", M.config.default.themes.light)
		-- Should not overwrite unspecified values
		assert.are.equal("default", M.config.default.colorscheme)
	end)

	it("merges persisted state on top of config", function()
		state.load = function()
			return { enabled = false, default = { background = "dark" } }
		end

		local mock_merge_called = false
		state.merge = function(base, stored)
			mock_merge_called = true
			return vim.tbl_deep_extend("force", base, stored)
		end

		core.setup({
			enabled = true,
			default = { background = "light" },
		})

		assert.is_true(mock_merge_called)
		assert.is_false(M.config.enabled) -- Overwritten by persisted state
		assert.are.equal("dark", M.config.default.background) -- Overwritten by persisted state
	end)

	it("sets enabled state from config", function()
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
	local original_config
	before_each(function()
		original_config = vim.deepcopy(require("colorful-times").config)
	end)
	after_each(function()
		require("colorful-times").config = original_config
	end)

	it("flips M.config.enabled", function()
		local M = require("colorful-times")
		local core = require("colorful-times.core")

		M.config.enabled = true
		core.setup(M.config)

		local before = M.config.enabled
		core.toggle()
		assert.are.equal(not before, M.config.enabled)

		core.toggle() -- restore
		assert.are.equal(before, M.config.enabled)
	end)
end)
