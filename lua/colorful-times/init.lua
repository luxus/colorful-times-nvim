-- Load the modules
local builder = require("colorful-times.builder")
local observer = require("colorful-times.observer")
local config = require("colorful-times.config")

-- Get the options from the config
local opts = config.setup()

-- Create a builder instance
local b = builder.new(opts.timeframes, opts.defaults)

-- Set the theme at startup
b:build()
observer.update_theme(b.theme, b.bg)

-- Add an observer to update the theme and background when the time changes
observer.add_observer(function(theme, bg)
	b:build()
	observer.update_theme(b.theme, b.bg)
end)

-- Return a table with a `setup()` function to allow the user to set the options
return {
	setup = config.setup,
}
