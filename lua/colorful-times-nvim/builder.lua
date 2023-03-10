local theme = require("colorful-times-nvim.theme")
local time = require("colorful-times-nvim.time")

local builder = {}

function builder.sorted_timeframes(opts)
	-- Sorts the timeframes in the order they should be applied to a window.
	-- Each timeframe is specified by a start time and a stop time.
	-- If a timeframe's start time is before its stop time, it is stored as a single timeframe.
	-- Otherwise, it is split into two timeframes, one applying from the start time to midnight,
	-- and the other applying from midnight to the stop time.
	-- The default theme and background are used for any gaps between the timeframes.
	--
	-- Parameters:
	--  opts: A table of options containing the default theme and background and the timeframes to use.
	--
	-- Returns:
	--  A table of sorted timeframes with associated themes and backgrounds.
	local frames = {}
	for i, v in ipairs(opts.timeframes) do
		local start_minutes = time.in_minutes(v.start)
		local stop_minutes = time.in_minutes(v.stop)
		local bg = v.bg or opts.default.bg
		local tf_theme = v.theme or opts.default.theme
		if start_minutes < stop_minutes then
			table.insert(frames, { start_minutes, stop_minutes, tf_theme, bg })
		else
			if start_minutes > 0 then
				table.insert(frames, { 0, stop_minutes, tf_theme, bg })
				table.insert(frames, { start_minutes, 24 * 60, opts.default.theme, opts.default.bg })
			else
				table.insert(frames, { 0, stop_minutes, theme, bg })
				table.insert(frames, { start_minutes, 24 * 60, opts.default.theme, opts.default.bg })
			end
		end
	end
	table.sort(frames, function(a, b)
		return a[1] < b[1]
	end)

	-- Fill any gaps between timeframes with the default theme and background
	local filled_frames = {}
	for i, frame in ipairs(frames) do
		table.insert(filled_frames, frame)
		local next_frame = frames[i + 1]
		if next_frame and next_frame[1] > frame[2] then
			local gap_start = frame[2]
			local gap_stop = next_frame[1]
			local gap_theme = opts.default.theme
			local gap_bg = opts.default.bg
			table.insert(filled_frames, { gap_start, gap_stop, gap_theme, gap_bg })
		end
	end

	return filled_frames
end

function builder.schedule_next_change(frames, opts)
	-- Schedules the next theme change.
	-- Parameters:
	--  frames: A table of time frames with associated themes and backgrounds.
	--  opts: A table containing the default theme and background.

	-- Set the next theme immediately before scheduling the timer
	local current_time = time.get()
	local current_minutes = time.in_minutes(current_time)
	local theme_name, bg_name = theme.current(frames, opts, current_minutes)
	theme.set(theme_name, bg_name)
	local next_theme = theme.next(frames, opts, current_minutes)
	-- Schedule the timer to execute the next theme change at the specified delay
	print(
		vim.notify(
			"Next theme change in "
				.. next_theme.delay
				.. " minutes. it will change to "
				.. next_theme.theme
				.. " with background "
				.. next_theme.bg
				.. "."
		)
	)
	vim.defer_fn(function()
		builder.schedule_next_change(frames, opts)
	end, next_theme.delay * 60 * 1000)
end

function builder.build(opts)
	local sorted = builder.sorted_timeframes(opts)
	-- print(vim.notify(vim.inspect(sorted)))
	builder.schedule_next_change(sorted, opts)
end

return builder
