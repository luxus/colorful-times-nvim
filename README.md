# Colorful Times

A fast, lightweight Neovim plugin that automatically changes your colorscheme based on time of day schedules or system appearance.

[![Neovim](https://img.shields.io/badge/Neovim-0.12%2B-green.svg?style=flat-square)](https://neovim.io/)
[![Lua](https://img.shields.io/badge/Made%20with%20Lua-blue.svg?style=flat-square&logo=lua)](https://lua.org)
[![CI](https://github.com/luxus/colorful-times-nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/luxus/colorful-times-nvim/actions/workflows/ci.yml)

## Features

* Time-based schedules for automatic theme changes throughout the day.
* System appearance sync that follows your OS light or dark mode.
* Interactive TUI for both schedule entries and default theme settings.
* State persistence saves your changes automatically.
* Zero startup impact using fully asynchronous background detection.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "luxus/colorful-times-nvim",
  lazy = false,
  priority = 1000, -- Colorscheme plugins must load first
  opts = {
    -- See configuration section below
  },
}
```

## Quick Start

```lua
require("colorful-times").setup({
  default = {
    colorscheme = "default",
    background = "system", -- "light", "dark", or "system"
  },
  schedule = {
    { start = "08:00", stop = "18:00", colorscheme = "tokyonight-day", background = "light" },
    { start = "18:00", stop = "08:00", colorscheme = "tokyonight-night", background = "dark" },
  },
})
```

## Configuration

Here are the default options.

```lua
{
  enabled = true,
  refresh_time = 5000, -- Milliseconds between system appearance polls
  system_background_detection = nil,
  system_background_detection_script = nil,
  default = {
    colorscheme = "default",
    background = "system",
    themes = { light = nil, dark = nil },
  },
  schedule = {},
  persist = true, -- Set to false to disable state persistence
}
```

The schedule manager TUI is fully inline: one floating window, one scratch buffer, live theme/background preview, and no extra edit popup.

## Commands

| Command | Description |
|---------|-------------|
| `:ColorfulTimes` | Open the interactive schedule manager |
| `:ColorfulTimesEnable` | Enable the plugin |
| `:ColorfulTimesDisable` | Disable the plugin |
| `:ColorfulTimesToggle` | Enable or disable the plugin |
| `:ColorfulTimesReload` | Reload configuration from disk |
| `:ColorfulTimesStatus` | Show the current resolved theme state, including session hold state |
| `:checkhealth colorful-times` | Run diagnostics |

## Schedule Manager TUI

Run `:ColorfulTimes` to open the interactive manager.

```
  ● ENABLED  Colorful Times 2.3.0
  Active  tokyonight-night • bg dark
  Source  schedule  · requested bg dark
  00:00 ···━━━━━━┃━━━━━━━━······················ 24:00  now 22:30
  ────────────────────────────────────────────────────────────
  DEFAULTS
    COLORSCHEME  default
    BACKGROUND   system
    LIGHT        dayfox
    DARK         nightfox
  ────────────────────────────────────────────────────────────
  Schedule
     START   STOP    COLORSCHEME                     BG        STATE
  ▸  08:00   18:00   tokyonight-day                  light
     18:00   08:00   tokyonight-night                dark      ● active
  ────────────────────────────────────────────────────────────
  Tab switch panel  j/k move  <CR> edit  a add schedule  d delete schedule
  H hold/release session theme  t toggle  r reload  q quit
```

Adding or editing opens an inline drawer in the same buffer. Theme selection expands into an inline filterable list; moving through choices previews live. Background selection is an inline segmented control for `system`, `light`, and `dark`.

### TUI Keymaps

| Key | Action |
|-----|--------|
| `j` / `Down` | Move down |
| `k` / `Up` | Move up |
| `Tab` | Switch focus between Defaults and Schedule |
| `a` | Add new schedule entry |
| `e` / `Enter` | Edit selected schedule row or focused default row |
| `d` / `x` | Delete selected schedule entry |
| `H` | Hold current theme for this session; press again to release |
| `t` | Toggle enabled or disabled |
| `r` | Reload configuration |
| `?` | Show help |
| `q` / `Esc` | Close TUI |

### Inline Editing

| Key | Action |
|-----|--------|
| `Tab` / `j` / `k` | Move between fields |
| `0-9` / `:` | Replace the active start or stop time; `14` becomes `14:00` |
| `Enter` | Open inline theme/background selector for the active field |
| `S` | Save draft and persist it |
| `O` | Hold current draft for this session; press again to release |
| `Esc` | Cancel and restore the preview snapshot |

New entries default to the current resolved colorscheme/background. Time defaults come from the displayed chronological schedule: `start` is the stop time of the last displayed entry, and `stop` is the start time of the first displayed entry. Empty schedules default to `08:00`–`18:00`.

### Session Hold

`H` holds the currently resolved theme/background for the rest of the Neovim session. In edit mode, `O` holds the current draft preview. While held, scheduled changes and system background changes do not apply a different theme. Press the same key again to release it. The hold is runtime-only, appears in the TUI/status output, and disappears on restart.

### Theme Resolution Order

Colorful Times resolves the active theme in this order:

1. Runtime session hold, when active
2. Matching schedule entry
3. `default.background`
4. `default.colorscheme` or `default.themes.light` / `default.themes.dark`

If the resolved background is `system`, the plugin keeps a safe fallback first
and then updates to the detected light or dark background asynchronously.

## System Background Detection

The plugin detects your system appearance based on your OS environment.

Priority order:

1. `system_background_detection` as a Lua function override
2. `system_background_detection` as a command table override
3. macOS auto-detection via `osascript`, with `defaults read` fallback
4. Linux custom script via `system_background_detection_script`
5. Linux KDE/GNOME auto-detection via `kreadconfig5`/`kreadconfig6` or `gsettings`

The function and command overrides work on any platform. The custom script is
Linux-only.

## Troubleshooting

### macOS Shortcuts and Automations

If you use macOS keyboard shortcuts or Automator scripts to toggle system appearance, the change might not be detected immediately. The plugin relies on an asynchronous polling mechanism. You might need to wait 1 to 2 poll cycles. You can adjust the `refresh_time` in your configuration to a lower value for faster detection. If the theme still doesn't update, run `:ColorfulTimesReload` to force a manual check.

### State Persistence

When `persist = true`, the plugin saves schedule edits, toggle state, and
default theme settings to disk immediately. `:ColorfulTimesReload` rebuilds
the live config from your setup config plus the persisted state file.
Live preview snapshots and session holds are never persisted.

State file location:
`~/.local/share/nvim/colorful-times/state.json`

If the TUI shows unexpected entries or the configuration breaks, you can reset the state by deleting this file. The plugin will rebuild it from your configuration on the next run.

## API

You can call these public functions directly in your Lua configuration.

```lua
local ct = require("colorful-times")

-- Initialize the plugin with options
ct.setup({ ... })

-- Toggle the plugin enabled/disabled state
ct.enable()
ct.disable()
ct.toggle()

-- Reload the configuration and re-apply colorschemes
ct.reload()

-- Open the schedule manager TUI
ct.open()

-- Inspect the current resolved state
ct.status()

-- Hold/release a runtime-only theme for this Neovim session
ct.pin_session("tokyonight-night", "dark", "dark")
ct.unpin_session()
```

## Performance

Colorful Times guarantees zero startup impact. It achieves this by lazily loading heavy modules on their first use. All background detection and file operations use fully asynchronous `vim.uv` APIs. The plugin also pre-caches schedules and uses an efficient LRU cache for time parsing to minimize CPU cycles.

## License

MIT License. See LICENSE for details.
