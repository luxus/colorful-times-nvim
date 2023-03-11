# colorful-times.nvim

a modern neovim plugin for changing the color scheme based on time of day.

## installation

```lua
 {
    "luxus/colorful-times.nvim",
    lazy = false,
    opts = {
        defaults = {
            theme = "everforest", -- the default theme to use if no timeframes match
            bg = "dark"
        }, -- the default background to use
        timeframes = { -- the timeframes to use
        { theme = "everforest", start = "09:00", stop = "17:00", bg = "light" }, -- day theme
        },
    }
}
```

## examples

here are a couple of examples to demonstrate how to use the plugin:

### example 1: changing color schemes

```lua
 {
  "luxus/colorful-times.nvim",
    lazy = false,
    opts = {
        defaults = {
            theme = "default",
            bg = "dark",
        },
        timeframes = {
            { theme = "rose-pine", start = "01:00", stop = "09:00", bg = "dark" },
            { theme = "tokyonight", start = "09:00", stop = "16:45", bg = "light" },
            { theme = "catppuccin", start = "16:45", stop = "21:45" },
        },
    }
 }
```

this example shows how to use the plugin to change the color scheme throughout the day. the plugin will change the to a specific color scheme of the time of day.

### example 2: working hours

```lua
 {
    "luxus/colorful-times.nvim",
    lazy = false,
    opts = {
        defaults = {
            theme = "tokyonight", -- the default theme to use if no timeframes match
            bg = "dark", -- the default background to use
        }
        timeframes = {
            { theme = "everforest", start = "09:00", stop = "17:00", bg = "light" },
        },
    }
}
```

this example shows how to use colorful-times to change the color scheme during working hours.
in this example, we're setting the default theme to tokyonight with a dark background, and we're defining a single timeframe that uses the everforest theme with a light background during working hours (i.e. from 9:00 am to 17:00).

note that if the current time does not match any of the defined timeframes, the color scheme will be set to the default theme and background.

### Chatgpt

This Plugin is mostly written by prompts i gave to Chatgpt, it was a fun experiment :D
