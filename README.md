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

The `snacks.nvim` plugin is optional. If installed, Colorful Times uses it to provide a fuzzy colorscheme picker with live preview in the TUI.

## Commands

| Command | Description |
|---------|-------------|
| `:ColorfulTimes` | Open the interactive schedule manager |
| `:ColorfulTimesToggle` | Enable or disable the plugin |
| `:ColorfulTimesReload` | Reload configuration from disk |
| `:checkhealth colorful-times` | Run diagnostics |

## Schedule Manager TUI

Run `:ColorfulTimes` to open the interactive manager.

```
┌─────────────────── Colorful Times ─────────────────────┐
│  [●] ENABLED  2.0.0                                     │
│ ────────────────────────────────────────────────────── │
│  DEFAULT  kanagawa                      BG system       │
│  LIGHT    kanagawa-lotus                               │
│  DARK     kanagawa-wave                                │
│ ────────────────────────────────────────────────────── │
│  START   STOP    COLORSCHEME                   BG       │
│ ────────────────────────────────────────────────────── │
│  06:00   18:00   tokyonight-day                light    │
│  18:00   06:00   tokyonight                    dark     │
│ ────────────────────────────────────────────────────── │
│  [a]dd [e]dit [d]el [c]olor [b]g [l]ight [n]ight ... │
└─────────────────────────────────────────────────────────┘
```

### TUI Keymaps

| Key | Action |
|-----|--------|
| `j` / `Down` | Move down |
| `k` / `Up` | Move up |
| `a` | Add new entry |
| `e` / `Enter` | Edit selected entry |
| `d` / `x` | Delete selected entry |
| `c` | Set the fallback default colorscheme |
| `b` | Set the fallback default background |
| `l` | Set or clear the system-light theme override |
| `n` | Set or clear the system-dark theme override |
| `t` | Toggle enabled or disabled |
| `r` | Reload configuration |
| `?` | Show help |
| `q` / `Esc` | Close TUI |

## System Background Detection

The plugin detects your system appearance based on your OS environment.

* **macOS**: Automatically detects appearance using `osascript` as the primary method, with a `defaults read` fallback.
* **Linux**: Auto-detects KDE and GNOME environments via `kreadconfig5`/`kreadconfig6` or `gsettings`.
* **Custom script**: Set `system_background_detection_script` to an absolute path pointing to a script that exits 0 for dark mode and 1 for light mode.
* **Custom function**: Set `system_background_detection` to a Lua function that returns `"dark"` or `"light"`.

## Troubleshooting

### macOS Shortcuts and Automations

If you use macOS keyboard shortcuts or Automator scripts to toggle system appearance, the change might not be detected immediately. The plugin relies on an asynchronous polling mechanism. You might need to wait 1 to 2 poll cycles. You can adjust the `refresh_time` in your configuration to a lower value for faster detection. If the theme still doesn't update, run `:ColorfulTimesReload` to force a manual check.

### State Persistence

When `persist = true`, the plugin saves schedule edits, toggle state, and
default theme settings to disk immediately. `:ColorfulTimesReload` rebuilds
the live config from your setup config plus the persisted state file.

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
ct.toggle()

-- Reload the configuration and re-apply colorschemes
ct.reload()

-- Open the schedule manager TUI
ct.open()
```

## Performance

Colorful Times guarantees zero startup impact. It achieves this by lazily loading heavy modules on their first use. All background detection and file operations use fully asynchronous `vim.uv` APIs. The plugin also pre-caches schedules and uses an efficient LRU cache for time parsing to minimize CPU cycles.

## License

MIT License. See LICENSE for details.
