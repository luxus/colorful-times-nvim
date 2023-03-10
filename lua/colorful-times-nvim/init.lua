local config = require("colorful-times-nvim.config")
local builder = require("colorful-times-nvim.builder")

local M = {}

function M.setup(opts)
	opts = vim.tbl_deep_extend("force", config, opts or {})
	builder.build(opts)
end

return M
