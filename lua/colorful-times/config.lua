local M = {}

-- Define default options
local defaults = {
	theme = "default",
	bg = "dark",
	timeframes = {},
}

-- Load user options and merge them with default options
M.opts = vim.tbl_deep_extend("keep", defaults, require("colorful-times.setup")())

return M
