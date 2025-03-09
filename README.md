# Colorful Times

A Neovim plugin that automatically changes your colorscheme based on time schedules, system appearance settings, or manual toggling.

## Features

- **Time-based colorscheme switching**: Automatically changes colorschemes based on your schedule
- **System appearance detection**: Follows your OS light/dark mode settings
- **Overnight schedule support**: Handles schedules that cross midnight
- **Low startup impact**: Uses lazy loading to minimize Neovim startup time
- **Customizable refresh times**: Control how often system appearance is checked
- **Manual controls**: Toggle the plugin on/off as needed

## Requirements

- Neovim >= 0.5.0
- For testing: [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

## Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'luxus/colorful-times-nvim',
  requires = { 'nvim-lua/plenary.nvim' }, -- Only needed for running tests
}
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'luxus/colorful-times-nvim',
  dependencies = { 'nvim-lua/plenary.nvim' }, -- Only needed for running tests
},
```

## Setup and Configuration

Add to your Neovim configuration:

```lua
require('colorful-times').setup({
  -- Schedule entries for when to change colorschemes
  schedule = {
    {
      start = "08:00", -- 8 AM
      stop = "18:00",  -- 6 PM
      colorscheme = "morning", -- your light colorscheme
      background = "light",    -- optional: "light", "dark", or "system"
    },
    {
      start = "18:00", -- 6 PM
      stop = "08:00",  -- 8 AM (next day)
      colorscheme = "evening", -- your dark colorscheme
      background = "dark",     -- optional
    },
  },
  
  -- Default settings when no schedule is active
  default = {
    colorscheme = "default",   -- fallback colorscheme
    background = "system",     -- "light", "dark", or "system" to follow OS settings
  },
  
  -- Other options
  enabled = true,              -- enable/disable the plugin
  refresh_time = 5000,         -- check system appearance every 5 seconds (in ms)
  
  -- Optional: custom command for Linux system background detection
  -- system_background_detection = "gsettings get org.gnome.desktop.interface color-scheme | grep -q 'prefer-dark'"
})
```

## Commands

Add these to your configuration for manual control:

```lua
-- Toggle plugin on/off
vim.api.nvim_create_user_command('ColorfulTimesToggle', function()
  require('colorful-times').toggle()
end, {})

-- Reload configuration
vim.api.nvim_create_user_command('ColorfulTimesReload', function()
  require('colorful-times').reload()
end, {})
```

## System Appearance Detection

- **macOS**: Automatically detects system appearance
- **Linux**: Requires custom detection command in configuration
- **Windows**: Not yet supported (contributions welcome!)

### Custom Linux Detection Example

For GNOME-based desktops:
```lua
system_background_detection = "gsettings get org.gnome.desktop.interface color-scheme | grep -q 'prefer-dark'"
```

For KDE:
```lua
system_background_detection = "kreadconfig5 --group 'General' --key 'ColorScheme' --file 'kdeglobals' | grep -q 'Dark'"
```

You can also provide a function that returns "light" or "dark":
```lua
system_background_detection = function()
  -- Custom detection logic
  return "dark" -- or "light"
end
```

## License

MIT

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests.