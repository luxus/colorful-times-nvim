# Colorful Times

A Neovim plugin that automatically changes your colorscheme based on a schedule, system settings, or manually. Optimized for zero-blocking startup time using modern Neovim `vim.uv` APIs.

## Requirements

- Neovim >= 0.12.0
- [snacks.nvim](https://github.com/folke/snacks.nvim) (optional — enables fuzzy colorscheme picker with live preview in the TUI; falls back to `vim.ui.*` without it)

## Features

- **Blazing Fast Startup**: Zero-blocking background initialization. Instantly applies fallback themes so your UI is rendered immediately, then seamlessly corrects the colorscheme if async system detection yields a different preference.
- **System Background Detection**: Supports automatic system dark/light mode detection on macOS and Linux (via auto-detect for KDE/GNOME or custom commands).
- **Time-based Scheduling**: Automatically change colorschemes based on the time of day.
- **Theme Fallbacks**: Configure distinct default colorschemes for both light and dark system backgrounds.
- **Schedule Manager TUI**: Keyboard-driven floating window to manage your schedule interactively.
- **Persistent State**: TUI changes are saved to disk and survive restarts.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "username/colorful-times",
  lazy = false, -- ensure it loads on start to apply colorschemes
  priority = 1000,
  opts = {
    -- see Configuration section below
  }
}
```

## Configuration

The plugin comes with the following default configuration:

```lua
require('colorful-times').setup({
  enabled = true,
  refresh_time = 5000, -- milliseconds between system appearance polls
  -- Custom command (table) or function returning 'dark'/'light' for Linux
  -- Table format: { "command", "arg1", "arg2" }
  system_background_detection = nil,
  persist = true, -- set false to disable TUI state persistence

  default = {
    colorscheme = "default",
    background = "system", -- "light", "dark", or "system"
    themes = {
      light = nil, -- colorscheme to use when background is light
      dark = nil,  -- colorscheme to use when background is dark
    },
  },

  -- Schedule allows defining specific colorschemes at times of day
  schedule = {
    -- { start = "06:00", stop = "18:00", colorscheme = "morning_theme", background = "light" },
    -- { start = "18:00", stop = "06:00", colorscheme = "night_theme", background = "dark" },
  },
})
```

## Schedule Manager TUI

Run `:ColorfulTimes` to open the interactive schedule manager:

```
┌─────────────────── Colorful Times ─────────────────────┐
│  [●] ENABLED  2.0.0                                     │
│ ────────────────────────────────────────────────────── │
│  START   STOP    COLORSCHEME                   BG       │
│ ────────────────────────────────────────────────────── │
│  06:00   18:00   tokyonight-day                light    │
│  18:00   06:00   tokyonight                    dark     │
│ ────────────────────────────────────────────────────── │
│  [a]dd [e]dit [d]el [t]oggle [r]eload [?]help [q]uit  │
└─────────────────────────────────────────────────────────┘
```

Edits are persisted to `~/.local/share/nvim/colorful-times/state.json` and survive restarts.
Set `persist = false` in your config to disable persistence.

## Commands

| Command | Description |
|---------|-------------|
| `:ColorfulTimes` | Open the schedule manager TUI |
| `:ColorfulTimesToggle` | Toggle the plugin on/off |
| `:ColorfulTimesReload` | Reload config from disk |

## API

- `require('colorful-times').setup(opts)`: Initialize the plugin with options.
- `require('colorful-times').toggle()`: Toggle the plugin enabled/disabled state.
- `require('colorful-times').reload()`: Reload the configuration and re-apply colorschemes.
- `require('colorful-times').open()`: Open the schedule manager TUI.

## Health Check

Run `:checkhealth colorful-times` to verify your setup.

## Performance Note

This plugin has been obsessed over to guarantee that it won't impact your Neovim start time. Lazy loading defers expensive module imports and function evaluations, while asynchronous `vim.uv` pipes spawn subprocesses to read your system background theme *after* the initial editor UI is unblocked.
