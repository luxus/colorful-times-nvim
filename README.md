# Colorful Times

A Neovim plugin that automatically changes your colorscheme based on a schedule, system settings, or manually. Optimized for zero-blocking startup time using modern Neovim `vim.uv` APIs.

## Requirements

- Neovim >= 0.10.0

## Features

- **Blazing Fast Startup**: Zero-blocking background initialization. Instantly applies fallback themes so your UI is rendered immediately, then seamlessly corrects the colorscheme if the background asynchronous system detection yields a different preference.
- **System Background Detection**: Supports automatic system dark/light mode detection on macOS and Linux (via auto-detect for KDE/GNOME or custom commands).
- **Time-based Scheduling**: Pre-process schedules to automatically change colorschemes based on the time of day.
- **Theme Fallbacks**: Configure distinct default colorschemes for both light and dark system backgrounds.

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
  refresh_time = 5000, -- Default refresh time in milliseconds to check system appearance
  system_background_detection = nil, -- Custom command (string) or function returning 'dark'/'light' for Linux

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

## API

- `require('colorful-times').setup(opts)`: Initialize the plugin with options.
- `require('colorful-times').toggle()`: Toggle the plugin enabled/disabled state.
- `require('colorful-times').reload()`: Reload the configuration and re-apply colorschemes.

## Performance Note

This plugin has been obsessed over to guarantee that it won't impact your Neovim start time. Lazy loading defers expensive module imports and function evaluations, while asynchronous `vim.uv` pipes spawn subprocesses to read your system background theme *after* the initial editor UI is unblocked.
