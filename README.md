# colorful-times.nvim

A Neovim plugin for changing the color scheme based on time of day.

## Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
  use {
    "luxus/colorful-times.nvim",
    config = function()
      -- Example 1: Changing Color Schemes
      require("colorful-times").setup({
        default_theme = "everforest", -- the default theme to use if no timeframes match
        default_bg = "dark", -- the default background to use
        timeframes = { -- the timeframes to use
          { theme = "rose-pine", start_time = "01:00", end_time = "09:00", bg = "dark" },
          { theme = "tokyonight", start_time = "09:00", end_time = "16:45", bg = "light" },
          { theme = "catppuccin", start_time = "16:45", end_time = "21:45" },
        },
      })

      -- Example 2: Working Hours
      require("colorful-times").setup({
        default_theme = "tokyonight", -- the default theme to use if no timeframes match
        default_bg = "dark", -- the default background to use
        timeframes = { -- the timeframes to use
          { theme = "everforest", start_time = "09:00", end_time = "17:00", bg = "light" },
        },
      })
    end,
  }

```

## Usage

Once installed, the plugin will automatically change the color scheme based on the current time of day and the specified timeframes. The plugin will set a timer for the next timeframe and will change the color scheme when that timeframe is reached.

## Timers

### Example 1: Changing Color Schemes

The following timers will be set:

From 00:00 to 01:00: default theme with dark background
From 01:00 to 09:00: rose-pine theme with dark background
From 09:00 to 16:45: tokyonight theme with light background
From 16:45 to 21:45: catppuccin theme with default background
From 21:45 to 00:00: default theme with dark background

The initial timer will be set to check the current time and set the color scheme for the current timeframe. A timer will be set for each timeframe to change the color scheme when that timeframe is reached. If you change the colorscheme or background by hand, no more timers will be set. Note that changing the color scheme or background by hand will also stop the current timer.

### Example 2: Working Hours

The following timer will be set:

From 09:00 to 17:00: everforest theme with light background

The initial timer will be set to check the current time and set the color scheme for the current timeframe. A timer will be set for the timeframe to change the color scheme when that timeframe is reached. If you change the colorscheme or background by hand, no more timers will be set. Note that changing the color scheme or background by hand will also stop the current timer.

### How does it work?

the plugin builds a table of defined timeframes and fill the gaps with default_bg and default_theme. if there are overlapping timeframes the next start_time will win. so every second of the day is covered
every timeframes will be run one by one and the table `timeframes_in_minutes` will be checked for the next timeframe and setup a timer
u can pause by running the toggle_timer()
