local builder = {}

-- This function takes a time in the format hh:mm, and returns the number of
-- minutes since midnight.
local function get_time_minutes(time)
	local hours, minutes = time:match("(%d+):(%d+)")
	return tonumber(hours) * 60 + tonumber(minutes)
end

-- This function sorts the timeframes in the order they should be applied to a
-- window. If a timeframe's start time is before its stop time, it is stored
-- as a single timeframe. Otherwise, it is split into two timeframes, one
-- applying from the start time to midnight, and the other applying from
-- midnight to the stop time.

local function sorted_timeframes(opts)
	local frames = {}
	local n = #opts.timeframes
	for i, v in ipairs(opts.timeframes) do
		local start_minutes = get_time_minutes(v.start)
		local stop_minutes = get_time_minutes(v.stop)
		if start_minutes < stop_minutes then
			table.insert(frames, { start_minutes, stop_minutes, v.theme, v.bg })
		else
			if start_minutes > 0 then
				table.insert(frames, { 0, stop_minutes, v.theme, v.bg })
				table.insert(frames, { start_minutes, 24 * 60, v.theme, v.bg })
			else
				table.insert(frames, { start_minutes, stop_minutes, v.theme, v.bg })
			end
		end
	end
	table.sort(frames, function(a, b)
		return a[1] < b[1]
	end)
	return frames
end

local function find_current_theme(frames, opts, current_time, current_minutes)
	-- Finds the theme that is currently active based on the current time.
	-- Parameters:
	--  frames: A table of time frames with associated themes and backgrounds.
	--  opts: A table containing the default theme and background.
	--  current_time: The current time as a Unix timestamp.
	--  current_minutes: The current time in minutes since midnight.
	-- Returns:
	--  The theme name and background name of the currently active theme.
	for _, v in ipairs(frames) do
		if current_minutes >= v[1] and current_minutes < v[2] then
			return v[3], v[4]
		end
	end
	return opts.default.theme, opts.default.bg
end

-- This code sets the colorscheme and background to the given values. It does
-- this by executing a vim command, which can be seen as a vim script
-- function.
local function set_theme(theme, bg)
	vim.cmd("colorscheme " .. theme)
	vim.o.background = bg
end

-- Schedule the theme change to occur after the current time
-- @param frames A table of frames with the format {start_time, stop_time, theme, bg}
-- @param opts A table of options with the format {transition, duration}
local function schedule_next_change(frames, opts, current_time, current_minutes)
	local theme, bg = find_current_theme(frames, opts, current_time, current_minutes)

	-- Loop over the timeframes and schedule the next change
	for i = 1, #frames do
		local next_index = (i % #frames) + 1
		local next_start, next_stop = frames[next_index][1], frames[next_index][2]

		if current_minutes >= next_start then
			local delay = next_stop - current_minutes
			if delay < 0 then
				delay = delay + 24 * 60
			end
			delay = delay * 60

			vim.defer_fn(function()
				set_theme(frames[next_index][3], frames[next_index][4])
				schedule_next_change(frames, opts, current_time + delay, next_stop)
			end, delay * 1000)

			return
		end
	end

	-- If we reach this point, it means that there are no more timeframes
	-- today, so we schedule the first timeframe for tomorrow.
	local first_start = frames[1][1]
	local delay = ((24 * 60) - current_minutes + first_start) * 60
	vim.defer_fn(function()
		set_theme(frames[1][3], frames[1][4])
		schedule_next_change(frames, opts, current_time + delay, first_start)
	end, delay * 1000)
end

-- This function builds the theme according to the options specified by the user
function builder.build(opts, current_time, current_minutes)
	local sorted = sorted_timeframes(opts)
	local theme, bg = find_current_theme(sorted, opts, current_time, current_minutes)
	set_theme(theme, bg)
	schedule_next_change(sorted, opts, current_time, current_minutes)
end

return builder
