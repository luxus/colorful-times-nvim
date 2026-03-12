-- Minimal init for benchmark
vim.opt.rtp:append(".")
local M = require("colorful-times.impl")
local uv = vim.uv

-- Make sure we have the default config
M.config = {
	system_background_detection = false,
}

-- Mock os.getenv to simulate Linux DE
local original_getenv = os.getenv
os.getenv = function(var)
	if var == "XDG_CURRENT_DESKTOP" then
		return "GNOME"
	end
	return original_getenv(var)
end

-- Force Linux system for testing
M._cached_sysname = "Linux"
M._cached_linux_de = nil

local iterations = 100
local completed = 0

local start_time = uv.hrtime()

local function on_complete(bg)
	completed = completed + 1
	if completed == iterations then
		local end_time = uv.hrtime()
		local duration_ms = (end_time - start_time) / 1e6
		print(
			string.format(
				"Completed %d iterations in %.2f ms (%.2f ms per call)",
				iterations,
				duration_ms,
				duration_ms / iterations
			)
		)

		-- Restore original
		os.getenv = original_getenv
		vim.cmd("qa!")
	end
end

for i = 1, iterations do
	M.get_system_background(on_complete, "dark")
end

-- Set a timeout just in case
vim.defer_fn(function()
	if completed < iterations then
		print("Timeout! Completed " .. completed .. " iterations.")
		vim.cmd("qa!")
	end
end, 10000)
