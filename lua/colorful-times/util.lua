local M = {}

local function time_to_minutes(time)
	local hours, minutes = time:match("(%d+):(%d+)")
	return tonumber(hours) * 60 + tonumber(minutes)
end

local function is_between_times(start_time, end_time, current_time)
	local current_minutes = current_time.hour * 60 + current_time.min
	start_time = time_to_minutes(start_time)
	end_time = time_to_minutes(end_time)

	-- Handle cases where start_time is greater than end_time (i.e. timeframe ends on next day)
	if start_time > end_time then
		end_time = end_time + 24 * 60
		if current_minutes < start_time then
			current_minutes = current_minutes + 24 * 60
		end
	end

	return current_minutes >= start_time and current_minutes < end_time
end

local function set_theme(theme, background, default_theme, default_bg)
	if vim.g.colors_name ~= theme or vim.o.background ~= background then
		vim.cmd("colorscheme " .. (theme or default_theme))
		vim.opt.background = background or default_bg
		vim.cmd("redraw!")
	end
end

local function setup_next_timer(opts, current_timer)
	local timeframes = opts.timeframes
	local default_bg = opts.default_bg
	local default_theme = opts.default_theme
	local timer

	-- If there's a timer running, stop it
	if current_timer then
		vim.fn.timer_stop(current_timer)
	end

	local current_time = os.date("*t")
	local current_minutes = current_time.hour * 60 + current_time.min

	-- Find the current timeframe
	local current_timeframe = nil
	for _, timeframe in ipairs(timeframes) do
		local start_time = timeframe.start_time or "00:00"
		local end_time = timeframe.end_time or "23:59"
		if is_between_times(start_time, end_time, current_time) then
			current_timeframe = timeframe
			break
		end
	end

	-- If there's no current timeframe, set the default theme and return
	if not current_timeframe then
		set_theme(default_theme, default_bg, default_theme, default_bg)
		return timer
	end

	-- Set the initial theme based on the current timeframe
	local current_bg = current_timeframe.bg or default_bg
	local current_theme = current_timeframe.theme or default_theme
	set_theme(current_theme, current_bg, default_theme, default_bg)

	-- Calculate the time until the next timeframe
	local next_timeframe = nil
	for _, timeframe in ipairs(timeframes) do
		local start_time = timeframe.start_time or "00:00"
		local end_time = timeframe.end_time or "23:59"
		if is_between_times(start_time, end_time, current_time) then
			next_timeframe = timeframe
			break
		end
	end

	-- If there's no next timeframe, set the default theme and return
	if not next_timeframe then
		set_theme(default_theme, default_bg, default_theme, default_bg)
		return timer
	end

	-- Calculate the time until the next timeframe
	local next_start_time = next_timeframe.start_time or "00:00"
	local next_end_time = next_timeframe.end_time or "23:59"
	local next_bg = next_timeframe.bg or default_bg
	local next_theme = next_timeframe.theme or default_theme

	local next_start_minutes = time_to_minutes(next_start_time)
	local delay_minutes = next_start_minutes - current_minutes

	-- Handle cases where the next timeframe starts on the next day
	if delay_minutes < 0 then
		delay_minutes = delay_minutes + 24 * 60
	end

	-- Set the timer for the next timeframe
	timer = vim.fn.timer_start(delay_minutes * 60 * 1000, function()
		set_theme(next_theme, next_bg, default_theme, default_bg)
		return setup_next_timer(opts, timer)
	end)

	return timer
end

function M.set_timeframes_timers(timeframes, default_bg, default_theme)
	return setup_next_timer({ timeframes = timeframes, default_bg = default_bg, default_theme = default_theme }, nil)
end

return M
