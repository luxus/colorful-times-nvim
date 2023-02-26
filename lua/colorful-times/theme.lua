local M = {}

function M.set(theme, bg)
	vim.api.nvim_command("colorscheme " .. theme)

	if bg == "dark" then
		vim.cmd("set background=dark")
	else
		vim.cmd("set background=light")
	end
end

return M
