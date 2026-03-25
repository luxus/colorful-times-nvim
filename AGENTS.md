# AGENTS.md - Colorful Times

A Neovim plugin that automatically changes colorschemes based on a schedule, system settings, or manually.

## Project Overview

- **Language**: Lua (Neovim plugins)
- **Test Framework**: plenary.nvim + busted
- **Neovim Requirement**: >= 0.12.0
- **Module Structure**: `lua/colorful-times/` with core, state, schedule, system, tui, health modules

---

## Build / Lint / Test Commands

**Run all tests:**
```bash
nvim --headless \
  -u tests/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"
```

**Run a single test file:**
```bash
nvim --headless \
  -u tests/minimal_init.vim \
  -c "PlenaryBustedFile tests/schedule_spec.lua"
```

**Health check:**
```bash
nvim --headless -c "checkhealth colorful-times" -c "qa!"
```

**Manual testing:**
```bash
nvim -u tests/minimal_init.vim
```

---

## Code Style

Follow the patterns already in the code. Key rules:

- **Formatting**: 2-space indent, no tabs, 80-char soft limit, UTF-8
- **Imports**: `local` for all `require` calls; top-of-file where possible; lazy-load non-critical modules (see `init.lua`)
- **Naming**: `snake_case` functions, `PascalCase` types/classes, `UPPER_SNAKE` constants, `_` prefix for private module-level vars and private locals (see `core.lua`, `system.lua`)
- **Annotations**: EmmyLua `---@param`/`---@return`/`---@class` on all public functions and types (see `init.lua`, `schedule.lua`)
- **Error handling**: `pcall` for risky calls, `vim.notify` with appropriate log levels (`ERROR`/`WARN`/`INFO`), early returns over deep nesting
- **Async**: `vim.schedule` for all main-thread ops called from async callbacks; always close timers properly (see `core.lua`)
- **Vim APIs**: `vim.bo[buf]`/`vim.wo[win]` for buffer/window options, `vim.api.nvim_*` over `vim.fn.*` when available, `vim.uv` for libuv; validate handles before use
- **vim.iter**: use for non-trivial table iteration chains (see `schedule.lua`)

---

## File Structure

```
lua/colorful-times/
├── init.lua      -- Plugin root, config class, lazy core loader
├── core.lua      -- Main logic, timer management, colorscheme application
├── state.lua     -- Persistence to JSON
├── schedule.lua  -- Schedule parsing and matching
├── system.lua    -- OS background detection (macOS/Linux)
├── tui.lua       -- Interactive schedule manager UI
└── health.lua    -- :checkhealth implementation

plugin/
└── colorful-times.lua  -- Registers :ColorfulTimes commands

tests/
├── minimal_init.vim
├── core_spec.lua
├── state_spec.lua
├── schedule_spec.lua
└── system_spec.lua
```

---

## Performance

- Lazy-load expensive modules (core, tui)
- Cache system detection results (`_sysname` in `system.lua`)
- Use `vim.uv` for async; avoid blocking on hot paths
- Always drain stdout/stderr pipes when spawning subprocesses (see `system.lua`)

---

## Documentation

- Update `doc/colorful-times.txt` when adding/changing commands
- Add EmmyLua annotations to all new public API functions
