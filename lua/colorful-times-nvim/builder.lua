local theme = require("colorful-times-nvim.theme")
local time = require("colorful-times-nvim.time")

local builder = {}
function builder.sorted_timeframes(opts)
	-- Sort the timeframes and fill gaps
	local frames = builder.sort_timeframes(opts.timeframes, {
		default_theme = opts.default.theme,
		default_bg = opts.default.bg,
	})
	frames = builder.fill_gaps(frames, opts.default.theme, opts.default.bg)

	return frames
end

-- Helper function to split a timeframe that starts later than it ends
local function split_timeframe(tf_start, tf_stop, tf_theme, tf_bg)
	-- Convert midnight to minutes
	local midnight = 24 * 60
	-- First part of the split timeframe runs until midnight
	local first_part = { tf_start, midnight, tf_theme, tf_bg }
	-- Second part of the split timeframe starts at midnight
	-- and runs until the stop time
	local second_part = { 0, tf_stop, tf_theme, tf_bg }
	return { first_part, second_part }
end

-- Main function to sort timeframes by start time
function builder.sort_timeframes(timeframes, default_opts)
	local frames = {}
	for _, tf in ipairs(timeframes) do
		local tf_start = time.in_minutes(time.convert_24_to_table(tf.start))
		local tf_stop = time.in_minutes(time.convert_24_to_table(tf.stop))
		local tf_bg = tf.bg or default_opts.default_bg
		local tf_theme = tf.theme or default_opts.default_theme

		if tf_start > tf_stop then
			-- Split timeframe into two parts
			local split_frames = split_timeframe(tf_start, tf_stop, tf_theme, tf_bg)
			for _, frame in ipairs(split_frames) do
				table.insert(frames, frame)
			end
		else
			-- Timeframe starts and ends on the same day
			table.insert(frames, { tf_start, tf_stop, tf_theme, tf_bg })
		end
	end

	table.sort(frames, function(a, b)
		return a[1] < b[1]
	end)

	return frames
end

function builder.fill_gaps(frames, default_theme, default_bg)
	local filled_frames = {}
	local last_stop = 0
	for _, frame in ipairs(frames) do
		local start = frame[1]
		local stop = frame[2]
		local theme = frame[3]
		local bg = frame[4]

		if start > last_stop then
			table.insert(filled_frames, { last_stop, start, default_theme, default_bg })
		end

		if stop - start > 0 then
			table.insert(filled_frames, { start, stop, theme, bg })
		end
		last_stop = stop
	end

	if last_stop < 1440 then
		table.insert(filled_frames, { last_stop, 1440, default_theme, default_bg })
	end

	return filled_frames
end

function builder.schedule_next_change(frames, opts)
	-- Schedules the next theme change.
	-- Parameters:
	--  frames: A table of time frames with associated themes and backgrounds.
	--  opts: A table containing the default theme and background.

	-- Set the next theme immediately before scheduling the timer
	local current_minutes = time.in_minutes(time.get())
	local theme_name, bg_name = theme.current(frames, opts, current_minutes)
	theme.set(theme_name, bg_name)
	local next_theme = theme.next(frames, opts, current_minutes)
	-- Schedule the timer to execute the next theme change at the specified delay
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
