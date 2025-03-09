# Colorful Times Neovim Plugin Guide

## Build and Test Commands
- Run all tests: `nvim --headless -c "lua require('plenary.test_harness').test_directory('tests')" -c 'q'`
- Run single test: `nvim --headless -c "lua require('plenary.test_harness').test_directory('tests', {filter='PATTERN'})" -c 'q'`
- Format code: `stylua lua/ tests/`

## Code Style Guidelines
- **Naming**: snake_case for variables and functions, PascalCase for classes/types
- **Types**: Use LuaLS annotations (`---@class`, `---@type`, etc.) for type safety
- **Documentation**: Add comment blocks before functions with descriptions and param types
- **Module Pattern**: Use `local M = {}` pattern with `return M` at the end
- **Error Handling**: Use `pcall` for error handling, with error messages via `vim.api.nvim_err_writeln`
- **Imports**: Place imports at top of file

## Project Structure
- Main module: `lua/colorful-times/init.lua`
- Tests: `tests/colorful_times_spec.lua`
- Test config: `tests/minimal_init.vim`
- Depends on Plenary.nvim for tests