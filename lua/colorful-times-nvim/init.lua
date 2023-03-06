local config = require("colorful-times-nvim.config")
local builder = require("colorful-times-nvim.builder")

local M = {}

function M.setup(opts)
	opts = vim.tbl_deep_extend("force", config, opts or {})
	local current_time = os.time()
	local current_minutes = (os.date("*t", current_time).hour * 60) + os.date("*t", current_time).min
	builder.build(opts, current_time, current_minutes)
end

return M
