# colorful-times v2 — Design Spec

**Date:** 2026-03-22  
**Status:** Approved  
**Neovim minimum:** 0.12  
**External dependency:** snacks.nvim (optional — TUI degrades gracefully without it)

---

## 1. Goals

Full rewrite of colorful-times.nvim targeting Neovim 0.12+. The rewrite:

- Drops all compatibility shims for Neovim < 0.12
- Restructures into focused, independently-testable modules
- Adds a keyboard-driven TUI (Table Manager) for managing schedules at runtime
- Persists TUI-made schedule changes to disk so they survive restarts
- Pauses the appearance poll timer when Neovim loses focus (zero CPU overhead when idle)
- Uses snacks.nvim for all user-facing UI (fuzzy picker, input, notifications) with a graceful fallback to `vim.ui.input` / `vim.ui.select` when snacks is absent
- Replaces all `nvim_err_writeln` calls with `vim.notify` log levels
- Adds `:checkhealth colorful-times` support
- Exposes three user-facing vim commands: `:ColorfulTimes`, `:ColorfulTimesToggle`, `:ColorfulTimesReload`

---

## 2. Module Structure

```
lua/colorful-times/
  init.lua       — stub: config defaults, metatable lazy-loader, type annotations
  core.lua       — state machine, timer orchestration, apply_colorscheme
  schedule.lua   — pure functions: parse, validate, preprocess, get_active_entry, next_change_at
  system.lua     — OS dark/light detection (macOS, Linux, custom)
  state.lua      — JSON persistence layer
  tui.lua        — Table Manager TUI (snacks.nvim integration)
  health.lua     — vim.health checkhealth module

plugin/
  colorful-times.lua  — registers vim commands, called at startup by lazy.nvim
```

---

## 3. Module Contracts

### 3.1 `init.lua`

Responsibilities:
- Declare the canonical `M.config` table with all defaults
- Apply a metatable so that accessing `M.setup`, `M.toggle`, `M.reload` triggers `require("colorful-times.core")` on first call
- Export type annotations (LuaLS `---@class` blocks) for LSP consumers
- Must not execute any logic, spawn processes, or define large functions

Config shape (unchanged from v1, backwards-compatible):

```lua
M.config = {
  enabled = true,
  refresh_time = 5000,
  system_background_detection = nil,
  default = {
    colorscheme = "default",
    background = "system",  -- "light" | "dark" | "system"
    themes = {
      light = nil,
      dark = nil,
    },
  },
  schedule = {},
  -- NEW in v2:
  persist = true,  -- whether TUI changes are written to state.json
}
```

### 3.2 `schedule.lua`

Pure module — no side effects, no `vim.api` calls except `vim.notify` for errors.

```lua
-- Parse "HH:MM" → integer minutes since midnight, or nil on invalid input
schedule.parse_time(str) -> integer|nil

-- Validate a raw schedule entry table; returns true or false + error string
schedule.validate_entry(entry) -> boolean, string?

-- Convert raw config schedule array into parsed entries; emits vim.notify on bad entries
schedule.preprocess(raw_schedule, default_background) -> ParsedEntry[]

-- Return the active ParsedEntry for `time_mins`, or nil
schedule.get_active_entry(parsed, time_mins) -> ParsedEntry|nil

-- Return minutes until the next schedule boundary after `time_mins`
-- Returns nil if the schedule is empty
schedule.next_change_at(parsed, time_mins) -> integer|nil
```

Types:
```lua
---@class ColorfulTimes.ScheduleEntry   (raw, from config)
---@field start string
---@field stop string
---@field colorscheme string
---@field background? string

---@class ColorfulTimes.ParsedEntry     (after preprocess)
---@field start_time integer
---@field stop_time integer
---@field colorscheme string
---@field background string
```

### 3.3 `system.lua`

Async OS appearance detection. Caches the OS name after first call.

```lua
-- Async — calls cb("dark"|"light")
-- fallback used if detection is unavailable or fails
system.get_background(cb, fallback)

-- Returns cached sysname (calls uv.os_uname() once, then caches)
system.sysname() -> string
```

Supported platforms:
- **macOS**: `uv.spawn("defaults", {"read", "-g", "AppleInterfaceStyle"})` — exit 0 = dark, non-zero = light
- **Linux**: auto-detect KDE (`kreadconfig6`/`kreadconfig5`) or GNOME (`gsettings`), or use `M.config.system_background_detection` (table of args, or function returning `"dark"|"light"`)
- **Other**: calls `cb(fallback)` immediately

### 3.4 `core.lua`

Owns all mutable state (timers, `previous_background`). Loaded on first `M.setup()` call.

```lua
core.setup(opts)     -- merge opts + state.load(), preprocess, apply, start timers
core.enable()        -- start timers, apply colorscheme
core.disable()       -- stop timers; calls apply_colorscheme() directly with M.config.enabled = false
                     --   (same two-phase logic: sync fallback first, async system detect if needed)
core.toggle()        -- flip M.config.enabled, call enable/disable
core.reload()        -- re-run setup with current M.config (does NOT call state.load() again;
                     --   caller is responsible for mutating M.config before calling reload)
core.apply_colorscheme()  -- two-phase:
                     --   1. synchronously apply fallback (previous_bg or vim.o.background or "dark")
                     --   2. if active background == "system", call system.get_background(cb) async;
                     --      cb calls set_colorscheme only if result differs from current previous_bg
```

Timer logic:
- **Schedule timer**: fires at the exact minute of the next schedule boundary (via `schedule.next_change_at`). One-shot, re-armed after each fire.
- **Appearance poll timer**: repeating, interval = `M.config.refresh_time`. On every tick, re-evaluates whether system background detection is needed: skip the `system.get_background` call if no active schedule slot uses `"system"` AND `M.config.default.background ~= "system"`. This evaluation happens on every tick (not at timer-start time), so it automatically reflects config changes after `core.reload()`. **Paused on `FocusLost`, resumed on `FocusGained`** via autocmds registered once in `core.setup()`.

State:
```lua
local timer           -- uv_timer_t|nil  schedule timer
local poll_timer      -- uv_timer_t|nil  appearance poll timer
local previous_bg     -- string|nil
local focused = true  -- bool, tracks FocusLost/FocusGained
```

### 3.5 `state.lua`

Persistence for TUI-made changes.

```lua
-- Returns path to state file
state.path() -> string   -- stdpath("data") .. "/colorful-times/state.json"

-- Load state file; returns {} if missing or parse error
state.load() -> table

-- Write table to state file (creates parent dirs if needed)
state.save(data)

-- Merge state on top of base config (state wins for schedule, enabled flag)
state.merge(base_config, stored) -> merged_config
```

State file schema:
```json
{
  "enabled": true,
  "schedule": [
    { "start": "06:00", "stop": "18:00", "colorscheme": "tokyonight-day", "background": "light" }
  ]
}
```

Only `enabled` and `schedule` are persisted. All other config (themes, refresh_time, etc.) always come from `init.lua` / the user's `setup()` call.

`state.merge()` treats a missing `schedule` key in stored as "no override" (user's config schedule is kept). An empty array `[]` wins and clears the user's schedule — this allows the TUI to explicitly remove all entries. Similarly, a missing `enabled` key leaves the user's config value intact.

### 3.6 `tui.lua`

Keyboard-driven floating window. Loaded only when `:ColorfulTimes` is called.

**Table Manager window:**
- Floating window, centered, ~60% width, sized to schedule length (min 10 rows)
- Renders schedule as a table: `START  STOP  COLORSCHEME  BACKGROUND`
- Cursor row highlighted
- Status bar: `[●] ENABLED` or `[○] DISABLED`  |  plugin version
- Keymaps:

| Key | Action |
|-----|--------|
| `j` / `↓` | Move cursor down |
| `k` / `↑` | Move cursor up |
| `a` | Add new entry |
| `e` / `Enter` | Edit entry under cursor |
| `d` / `x` | Delete entry under cursor (confirm prompt) |
| `t` | Toggle plugin enabled/disabled |
| `r` | Reload config |
| `?` | Show keymap help |
| `q` / `Esc` | Close TUI |

**Add / Edit form** (sequential, snacks-powered):

1. `Snacks.input` → start time (validates `HH:MM` inline, re-prompts on error)
2. `Snacks.input` → stop time (same validation)
3. `Snacks.picker.pick` with custom finder → colorscheme fuzzy picker
   - Items: `vim.fn.getcompletion("", "color")` — all installed colorschemes
   - `on_change` callback: applies colorscheme live as user moves through list (reverts on cancel)
4. `vim.ui.select` → background: `["light", "dark", "system"]`
5. On confirm: validate full entry → update `M.config.schedule` in memory → if `persist = true`, `state.save({ enabled = M.config.enabled, schedule = M.config.schedule })` → `core.reload()` (which uses the already-mutated `M.config`, not state.json) → re-render table.
   - `persist = false`: skips `state.save()`; `M.config.schedule` is mutated in memory but not persisted. `core.reload()` still uses the mutated in-memory config, so TUI changes are effective for the session.

**Graceful degradation** (no snacks):
- Steps 1–2: `vim.ui.input`
- Step 3: `vim.ui.select` over colorscheme list (no live preview)
- Step 4: `vim.ui.select`

**Delete confirm**: `vim.ui.select({"Yes", "No"}, ...)` — no snacks dependency needed here.

### 3.7 `health.lua`

```lua
-- Called by :checkhealth colorful-times
health.check()
```

Checks:
- Neovim version >= 0.12
- `vim.uv` available
- snacks.nvim present (info, not error — it's optional)
- State file readable/writable
- Each schedule entry is valid (reports bad entries)
- Current colorscheme is loadable

### 3.8 `plugin/colorful-times.lua`

Registers vim commands at startup. Does not `require` any heavy module.

```lua
vim.api.nvim_create_user_command("ColorfulTimes",       ..., {})
vim.api.nvim_create_user_command("ColorfulTimesToggle", ..., {})
vim.api.nvim_create_user_command("ColorfulTimesReload", ..., {})
```

Each command's callback does `require("colorful-times.core").<fn>()` on demand.

---

## 4. Data Flow

```
startup
  └─ init.lua loaded (config defaults only)
  └─ plugin/colorful-times.lua loaded (registers commands only)
  └─ user calls setup(opts)
       └─ core.lua loaded
       └─ state.load() → merge over opts
       └─ schedule.preprocess()
       └─ core.apply_colorscheme()  ← instant fallback, then async system check
       └─ schedule_next_change()
       └─ start_poll_timer()
       └─ register FocusLost / FocusGained autocmds

runtime (schedule boundary)
  └─ schedule timer fires
  └─ core.apply_colorscheme()
  └─ schedule_next_change() ← re-arm

runtime (OS appearance change)
  └─ poll timer fires (only if focused)
  └─ system.get_background(cb)
  └─ if bg != previous_bg → core.apply_colorscheme()

TUI edit
  └─ :ColorfulTimes → tui.open()
  └─ user edits entry
  └─ schedule.validate_entry()
  └─ M.config.schedule updated
  └─ state.save()
  └─ core.reload()
  └─ tui re-renders
```

---

## 5. API (public, backwards-compatible)

```lua
require("colorful-times").setup(opts)   -- initialize
require("colorful-times").toggle()      -- enable/disable
require("colorful-times").reload()      -- reload config
```

New in v2:
```lua
require("colorful-times").open()  -- open TUI; same as :ColorfulTimes command
                                  -- lazy-loads tui.lua, then calls tui.open()
```

---

## 6. Testing Strategy

- Each module tested in isolation via plenary.nvim busted
- `schedule.lua` tests: pure Lua, no Neovim mocks needed
- `system.lua` tests: mock `uv.spawn` via function injection
- `core.lua` tests: mock `schedule`, `system`, `uv` timers; test state transitions
- `state.lua` tests: use a temp directory per test
- `tui.lua`: integration-level only (pending, environment-dependent)
- CI: Neovim stable + nightly; test matrix kept, Lua version matrix dropped (Neovim 0.12 ships LuaJIT only)

---

## 7. Breaking Changes from v1

| v1 | v2 |
|----|----|
| `vim.loop` alias | `vim.uv` only |
| `nvim_err_writeln` | `vim.notify(msg, vim.log.levels.ERROR)` |
| No persistence | `state.json` (opt-out with `persist = false`) |
| No TUI | `:ColorfulTimes` |
| No `:checkhealth` | `health.lua` |
| `impl.lua` monolith | 5 focused modules |
| Neovim >= 0.10 | Neovim >= 0.12 |

---

## 8. Files to Delete / Superseded

- `lua/colorful-times/impl.lua` — replaced by `core.lua`, `schedule.lua`, `system.lua`, `state.lua`, `tui.lua`, `health.lua`
- `tests/colorful_times_spec.lua` — replaced by per-module test files under `tests/`
- `tests/minimal_init.vim` — updated to add snacks.nvim stub for TUI tests

---

## 9. Out of Scope

- Windows OS appearance detection (no `uv.spawn` equivalent readily available; falls back to `vim.o.background`)
- Event-driven (reactive) appearance detection — smart polling with FocusLost pause is sufficient
- Any dependency other than snacks.nvim (optional)
