# colorful-times.nvim

A Neovim plugin for changing the color scheme based on time of day.

## Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
  use {
    "luxus/colorful-times.nvim",
    config = function()
      require("colorful-times").setup({
        default_theme = "kanagawa", -- the default theme to use if no timeframes match
        default_bg = "dark", -- the default background to use
        timeframes = { -- the timeframes to use
          { theme = "rose-pine", start_time = "01:00", end_time = "09:00", bg = "dark" },
          { theme = "tokyonight", start_time = "09:00", end_time = "16:45", bg = "light" },
          { theme = "catppuccin", start_time = "16:45", end_time = "21:45" },
        },
      })
    end,
  }
```

## Usage

Once installed, the plugin will automatically change the color scheme based on the current time of day and the specified timeframes. The plugin will set a timer for the next timeframe and will change the color scheme when that timeframe is reached.

## Timers

The following timers will be set:

From 00:00 to 01:00: default theme with dark background
From 01:00 to 09:00: rose-pine theme with dark background
From 09:00 to 16:45: tokyonight theme with light background
From 16:45 to 21:45: catppuccin theme with default background
From 21:45 to 00:00: default theme with dark background
The initial timer will be set to check the current time and set the color scheme for the current timeframe. A timer will be set for each timeframe to change the color scheme when that timeframe is reached. If you change the colorscheme or background by hand, no more timers will be set.

## Manual control

If you want to stop the timer, you can call `require("colorful-times").stop_timer()`.

If you want to restart the timer, you can call `require("colorful-times").restart_timer()`. This will stop the current timer and set up a new one based on the current time and the specified timeframes.
