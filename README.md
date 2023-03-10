# colorful-times.nvim

a modern and very fast neovim plugin for changing the color scheme based on time of day.

## installation

using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  "luxus/colorful-times.nvim",
  config = function()
    -- example 1: changing color schemes
    require("colorful-times").setup({
      defaults = {
        theme = "everforest", -- the default theme to use if no timeframes match
        bg = "dark"
      }, -- the default background to use
      debug = true,
      timeframes = { -- the timeframes to use
        { theme = "everforest", start = "09:00", stop = "17:00", bg = "light" }, -- day theme
      },
    })
  end,
}
```

## examples

here are a couple of examples to demonstrate how to use the plugin:

### example 1: changing color schemes

```lua
require("colorful-times").setup({
  defaults = {
    theme = "default",
    bg = "dark",
  }
  debug = true,
  timeframes = {
    { theme = "rose-pine", start = "01:00", stop = "09:00", bg = "dark" },
    { theme = "tokyonight", start = "09:00", stop = "16:45", bg = "light" },
    { theme = "catppuccin", start = "16:45", stop = "21:45" },
  },
})
```

this example shows how to use the plugin to change the color scheme throughout the day. the plugin will change the color scheme every few hours to match the time of day.

### example 2: working hours

```lua
require("colorful-times").setup({
  defaults = {
    theme = "tokyonight", -- the default theme to use if no timeframes match
     bg = "dark", -- the default background to use
  }
  debug = false,
  timeframes = {
    { theme = "everforest", start = "09:00", stop = "17:00", bg = "light" },
  },
})
```

this example shows how to use colorful-times to change the color scheme during working hours.
in this example, we're setting the default theme to tokyonight with a dark background, and we're defining a single timeframe that uses the everforest theme with a light background during working hours (i.e. from 9:00 am to 5:00 pm).

note that if the current time does not match any of the defined timeframes, the color scheme will be set to the default theme and background.

usage
once installed and set up, the plugin will automatically change the color scheme based on the current time of day and the specified timeframes. the plugin will set a timer for the next timeframe and will change the color scheme when that timeframe is reached.

you can manually toggle the timer on and off by running the toggle_timer() function, which is provided by the plugin. this can be useful if you want to temporarily disable the automatic color scheme switching.

### how does it work?

#### Folder structure

colorful-times.nvim/
├── lua/
│ └── colorful_times/
│---- ├── config.lua
│---- ├── init.lua
│---- ├── strategy.lua
│---- ├── theme_observer.lua
│---- ├── timeframe_builder.lua
│---- ├── theme.lua
│---- └── utils.lua

└── README.md

#### improvements

we use design principles strategy observing and building
we abstract the code into modules
we use vim.api.nvim_set_option instead of cmd
we use vim.schedule instead of vim.loop.timer_start
we sort the table by a for loop instead of table.sort
we wrap the vim.notify in vim.schedule_wrap
we cache the vim.api.nvim_get_option calls in module-level-variables

the lua code is split up in init.lua, config.lua and utils.lua
init.lua will hold the main code. and execute most of the functions

config.lua will handle the defaults and the debug default. (no timeframes are created by default)
it will handle the setup() and return opts

theme.lua will hold
function set_theme() and find_themes()

utils.lua will have all the helper that are very generic
time_to_minutes()
get_current_minute()
generate_gap_filler()
generate_table() and caching the result
toggle_themetimer()
setup_themetimer()

#### on setup

when you setup the addon you have to setup define a default_theme, a default_background, and a table with timeframes.
in this timeframes table you have to set a themename, start and stop in 24 hour format and optionally a background (dark or light)
it will convert all start times to `startminute` (for reference `startminute` is the start time converted from 24 hour to minute at the day so 03:30 is 210)
if a timeframe starts at 23:00 the startminute is 1380. if the stop of this timeframe is 02:00 the timer should fire 180 mins later. if there is no
timeframe after this one it should close the gap to the first one if the first timeframe starts at 7:00 it should close the gap with the default theme and set the
timer to 300 mins
it expects a that u call setup() on installation with at least 1 timeframe, changes to the defaults are optional but recommended because the default theme doesnt look that great. here a example again

```lua
use {
  "luxus/colorful-times.nvim",
  config = function()
    -- example 1: changing color schemes
    require("colorful-times").setup({
      defaults = {
        theme = "everforest", -- the default theme to use if no timeframes match
        bg = "dark" -- the default background to use
      },
      debug = true,
      timeframes = { -- the timeframes to use
        { theme = "everforest", start = "09:00", stop = "17:00", bg = "light" }, -- day theme
      },
    })
  end,
}
```

#### on start

with this information it will create a table with start times for all timeframes,
it converts the 24 hour formated time to `startminute` with the `string.match()`
it will handle stop times that are before start by expecting they cross midnight by splitting it up to 2 timeframes and start the second one on midnight
any gaps based on the stop and start times in the timeframes will be covered by additional `startminute` with the default theme and background. if there is no timeframe in the evening until the morning, create one that starts after the last timeframe and one that starts at 0 minutes aka midnight
after the table is generated, sorted and cached it should move on to the next step
with this table it knows what theme and background is have to set.
the correct theme would be the startminute that is closest to the `currentminute` of the day but the same or smaller
it when finds the right theme it will set the theme and background and create a timer for the next `startminute`

#### on timer

when the timer fires it will check if theme or background is changed by looking in the table and comparing the theme with the `startminute` that lower then the `currentminute`, this function could be the same to find out what theme it should set except this time the start minute cannot be the same and should be lower.
if the theme has changed toggle the themetimer to off
if not change the theme to the theme and background with start minute equals current minute. setup a countdown timer to the next `starttime` (in minutes of the day) from the table

### keymaps

there is a function themetimertoggle that can toggle or turn off (by a optional bool) the timer creation

### notes

i try to be as efficient and optimistic as possible. with the usage of stopminute it can detect gaps and fill them with new startminute with default theme and background. because only the starttime in minutes of the day is saved on the table we don't expecting many edge cases.
it will only run a timer that fires on the next startminute, no regular timers are used
the code should be very optimised and quick it uses vim.notify() without any arguments to send debug messages. this debug messages can be enabled in the setup()

for keymap you can add something like this for yourself

```lua
vim.api.nvim_set_keymap("n", "<Leader>ct", "<cmd>lua colorful_times.themetimertoggle()<CR>", { noremap = true, silent = true })
```

### Chatgpt

Write A fullfeatured plugin. use all the infos in this readme as rules to create the code.
