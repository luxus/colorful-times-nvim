-- Neovim Lua globals
std = "luajit"
globals = { "vim" }
read_globals = { "describe", "it", "before_each", "after_each", "assert", "pending" }
max_line_length = false
codes = true

-- Ignore unused self parameter (common in Lua OOP)
ignore = { "212/self" }

-- Exclude generated files
exclude_files = { ".git/", "nvim-linux*/" }
