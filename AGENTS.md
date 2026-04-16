# AGENTS.md - Colorful Times

A Neovim plugin that automatically changes colorschemes based on a schedule, system settings, or manually.

## Project Overview

- **Language**: Lua (Neovim plugins)
- **Test Framework**: plenary.nvim + busted
- **Neovim Requirement**: >= 0.12.0
- **Module Structure**: `lua/colorful-times/` with core, state, schedule, system, tui, health modules
- **Performance Focus**: Zero startup impact, async operations, intelligent caching

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
├── health_spec.lua
├── init_spec.lua
├── state_spec.lua
├── schedule_spec.lua
└── system_spec.lua

doc/
└── colorful-times.txt  -- Vim help documentation
```

---

## Performance Optimizations

The codebase has been heavily optimized for performance:

### Caching Strategies

1. **Schedule Preprocessing** (`core.lua`): Cached parsed schedule to avoid re-parsing on every theme check
2. **Time Parsing** (`schedule.lua`): Deterministic memo cache for HH:MM → minutes conversion
3. **Next Change Calculation** (`schedule.lua`): Single-entry cache for `next_change_at` results
4. **Snacks Detection** (`tui.lua`): Cached result of `pcall(require, "snacks")`
5. **Platform Detection** (`system.lua`): Cached `uv.os_uname().sysname` result

### Lookup Optimizations

- Replaced `vim.tbl_contains()` with static lookup tables (O(1) vs O(n))
- Lazy loading uses O(1) key table instead of `vim.tbl_contains()`
- Background validation uses `VALID_BACKGROUNDS[bg]` lookup

### Async Patterns

- All file I/O via `vim.uv` (non-blocking)
- System detection uses `uv.spawn()` with proper pipe draining
- Timer management with proper cleanup (`is_closing()` checks)

---

## Key Implementation Details

### Timer Management (`core.lua`)

Two timer types:
- `_timers.schedule`: Fires at next schedule boundary (one-shot, rescheduled after firing)
- `_timers.poll`: Recurring timer for system background detection (only when needed)

Poll callbacks are single-flight: do not spawn a new detection run while the
previous run is still in flight.

Both use proper cleanup:
```lua
local function stop_timer(t)
  if t and not t:is_closing() then
    t:stop()
    t:close()
  end
end
```

### Schedule Matching (`schedule.lua`)

- Overnight spans handled by adding `MINUTES_PER_DAY` (1440) when `stop <= start`
- Boundaries are inclusive start, exclusive stop
- Uses `vim.iter` for modern iteration patterns

### State Persistence (`state.lua`)

- Atomic rename for backup (fallback to copy+delete)
- JSON encoding/decoding with validation
- Graceful handling of corrupted state files
- Path: `vim.fn.stdpath("data") .. "/colorful-times/state.json"`

### System Detection (`system.lua`)

Priority order:
1. User-provided function (`cfg.system_background_detection`)
2. User-provided command table
3. macOS: `osascript`, then `defaults read -g AppleInterfaceStyle` as fallback
4. Linux custom script (`cfg.system_background_detection_script`)
5. Linux KDE: `kreadconfig6` or `kreadconfig5`
6. Linux GNOME: `gsettings get org.gnome.desktop.interface color-scheme`

All detection is async via `uv.spawn()`.

---

## Testing Guidelines

- Each module has corresponding `*_spec.lua` file
- Tests reload modules with `package.loaded["..."] = nil` for isolation
- Cache behavior tested explicitly (hit/miss/invalidation)
- Use `after()` cleanup hooks for test isolation
- Mock `os.getenv` and `uv.spawn` for system detection tests

---

## Documentation

- Update `doc/colorful-times.txt` when adding/changing commands
- Add EmmyLua annotations to all new public API functions
- Keep README.md in sync with actual features
- Update this AGENTS.md when architectural patterns change

---

## Common Pitfalls

1. **Timer leaks**: Always check `t:is_closing()` before `t:close()`
2. **Cache invalidation**: Clear `_parsed_schedule` when config changes
3. **Async callbacks**: Wrap Vim API calls in `vim.schedule()` when called from uv callbacks
4. **State validation**: Validate before save, not just after load
5. **Pipe draining**: Always drain stdout/stderr in `uv.spawn()` callbacks to prevent blocking

---

## External Dependencies

- **Required**: Neovim >= 0.12.0 (for `vim.uv`)
- **Optional**: snacks.nvim (for fuzzy colorscheme picker in TUI)
- **Test**: plenary.nvim (busted-compatible test runner)
