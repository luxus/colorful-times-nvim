# 🎨 Colorful Times

A fast, lightweight Neovim plugin that automatically changes your colorscheme based on time-of-day schedules or system appearance (light/dark mode).

[![Neovim](https://img.shields.io/badge/Neovim-0.12%2B-green.svg?style=flat-square)](https://neovim.io/)
[![Lua](https://img.shields.io/badge/Made%20with%20Lua-blue.svg?style=flat-square&logo=lua)](https://lua.org)

## ✨ Features

- ⏰ **Time-based schedules** — Define colorschemes for different times of day
- 🌓 **System appearance sync** — Automatically follow your OS light/dark mode
- ⚡ **Zero startup impact** — Fully asynchronous with `vim.uv`
- 🖥️ **Interactive TUI** — Keyboard-driven schedule manager (`:ColorfulTimes`)
- 💾 **State persistence** — Changes saved automatically
- 🔧 **Highly configurable** — Custom detection scripts, function overrides

## 📦 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "your-username/colorful-times.nvim",
  lazy = false,  -- Or use lazy loading with your preferred event
  opts = {
    -- your configuration
  },
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  "your-username/colorful-times.nvim",
  config = function()
    require("colorful-times").setup({
      -- your configuration
    })
  end
}
```

## 🚀 Quick Start

```lua
require("colorful-times").setup({
  default = {
    colorscheme = "default",
    background = "system",  -- "light", "dark", or "system"
  },
  schedule = {
    { start = "08:00", stop = "18:00", colorscheme = "tokyonight-day", background = "light" },
    { start = "18:00", stop = "08:00", colorscheme = "tokyonight-night", background = "dark" },
  },
})
```

## ⚙️ Configuration

### Default Options

```lua
{
  enabled = true,                    -- Enable the plugin
  refresh_time = 5000,              -- Milliseconds between system polls
  persist = true,                    -- Save TUI changes to disk

  default = {
    colorscheme = "default",
    background = "system",          -- "light", "dark", or "system"
    themes = {
      light = nil,                  -- Colorscheme when background is "light"
      dark = nil,                   -- Colorscheme when background is "dark"
    },
  },

  schedule = {},                    -- Time-based schedule entries

  -- Linux only: custom detection (auto-detected for KDE/GNOME)
  system_background_detection = nil,
  system_background_detection_script = nil,
}
```

### Schedule Format

Each schedule entry defines a time range and the theme to use:

```lua
schedule = {
  {
    start = "08:00",           -- Start time (HH:MM, 24-hour)
    stop = "18:00",            -- Stop time (exclusive)
    colorscheme = "gruvbox",     -- Colorscheme name
    background = "light",      -- "light", "dark", or "system"
  },
  -- Overnight spans work too!
  { start = "22:00", stop = "06:00", colorscheme = "catppuccin-mocha", background = "dark" },
}
```

### System Background Detection

**macOS**: Works automatically via `defaults read`.

**Linux KDE/GNOME**: Auto-detected via `kreadconfig5/6` or `gsettings`.

**Custom script** (Linux):
```lua
system_background_detection_script = "/path/to/detect-theme.sh"
-- Script should exit 0 for dark, 1 for light
```

**Custom function**:
```lua
system_background_detection = function()
  -- Return "dark" or "light"
  return os.execute("some-command") and "dark" or "light"
end
```

## 🎮 Commands

| Command | Description |
|---------|-------------|
| `:ColorfulTimes` | Open the interactive schedule manager |
| `:ColorfulTimesToggle` | Enable/disable the plugin |
| `:ColorfulTimesReload` | Reload configuration from disk |
| `:checkhealth colorful-times` | Run diagnostics |

### TUI Keymaps

When the schedule manager is open:

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `a` | Add new entry |
| `e` / `Enter` | Edit selected entry |
| `d` / `x` | Delete selected entry |
| `t` | Toggle enabled/disabled |
| `r` | Reload configuration |
| `?` | Show help |
| `q` / `Esc` | Close TUI |

## 📁 State Persistence

When `persist = true` (default), changes made via the TUI are saved to:

```
~/.local/share/nvim/colorful-times/state.json
```

The persisted state is merged with your config on startup, with your config taking precedence.

## 🔌 API

```lua
local ct = require("colorful-times")

-- Setup the plugin
ct.setup({ ... })

-- Toggle on/off
ct.toggle()

-- Reload configuration
ct.reload()

-- Open TUI
ct.open()

-- Manually apply colorscheme
ct.apply_colorscheme()
```

## 🏥 Health Check

Run `:checkhealth colorful-times` to verify:

- ✓ Neovim version (>= 0.12)
- ✓ vim.uv availability
- ✓ snacks.nvim (optional, for better TUI)
- ✓ State directory writable
- ✓ Schedule entries valid

## ⚡ Performance

Colorful Times is optimized for zero startup impact:

- Lazy-loads heavy modules on first use
- Uses `vim.uv` for all async operations
- Caches preprocessed schedules
- Efficient LRU cache for time parsing
- Minimal memory footprint

## 📝 License

MIT License — see [LICENSE](./LICENSE) for details.

## 🙏 Credits

Built with ❤️ for the Neovim community.
