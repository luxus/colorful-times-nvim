local util = require("colorful-times.util")

local default_opts = {
	default_theme = "default",
	default_bg = "dark",
	timeframes = {},
}

local timer

local function stop_timer()
	if timer ~= nil and vim.fn.timer_info(timer) ~= -1 then
		vim.fn.timer_stop(timer)
	end
end

local function setup(opts)
	opts = vim.tbl_deep_extend("keep", opts or {}, default_opts)
	util.set_timeframes_timers(opts.timeframes, opts.default_bg, opts.default_theme)

	-- Set default theme
	if not opts.timeframes or #opts.timeframes == 0 then
		util.set_theme(opts.default_theme, opts.default_bg, opts.default_theme, opts.default_bg)
	end
end

return {
	setup = setup,
	stop_timer = stop_timer,
	restart_timer = function(opts)
		stop_timer()
		setup(opts)
	end,
}
