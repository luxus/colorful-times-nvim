local config = require("colorful-times-nvim.config")
local builder = require("colorful-times-nvim.builder")

local M = {}
M.enabled = true

function M.toggle()
	M.enabled = not M.enabled
	builder.set_enabled(M.enabled)
	if M.enabled then
		builder.schedule_next_change_if_enabled(builder.sorted_timeframes(config), config)
	end
end

function M.setup(opts)
	opts = vim.tbl_deep_extend("force", config, opts or {})
	builder.set_enabled(M.enabled)
	builder.schedule_next_change_if_enabled(builder.sorted_timeframes(opts), opts)
end

return M
