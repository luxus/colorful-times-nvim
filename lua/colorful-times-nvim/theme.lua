local theme = {}

-- This code sets the colorscheme and background to the given values. It does
-- this by executing a vim command, which can be seen as a vim script
-- function.
function theme.set(theme_name, bg_name)
	vim.cmd("colorscheme " .. theme_name)
	vim.api.nvim_set_option("background", bg_name)
end

function theme.current(frames, opts, current_minutes)
	-- Finds the theme that is currently active based on the current time.
	-- Parameters:
	-- frames: A table of time frames with associated themes and backgrounds.
	-- opts: A table containing the default theme and background.
	-- current_minutes: The current time in minutes since midnight.
	-- Returns:
	-- The theme name and background name of the currently active theme.
	for _, v in ipairs(frames) do
		if current_minutes >= v[1] and current_minutes < v[2] then
			return v[3], v[4] or opts.default.bg
		end
	end
	return opts.default.theme, opts.default.bg
end

-- This function finds the theme that will be active after the current timeframe ends.
-- Parameters:
-- frames: A table of time frames with associated themes and backgrounds.
-- opts: A table containing the default theme and background.
-- current_minutes: The current time in minutes since midnight.
-- Returns:
-- A table containing the theme name and background name of the next theme,
-- and the number of minutes until the next theme starts.

function theme.next(frames, opts, current_minutes)
	local next_delay = nil
	local theme_name, bg_name
	local i

	for idx, v in ipairs(frames) do
		local start_minutes = v[1]
		local stop_minutes = v[2]
		theme_name = v[3]
		bg_name = v[4]

		if current_minutes >= start_minutes and current_minutes < stop_minutes then
			-- Current timeframe is active
			next_delay = stop_minutes - current_minutes
			i = idx
			break
		else
			-- Next timeframe is about to start
			next_delay = start_minutes - current_minutes
			i = idx
			break
		end
	end

	if next_delay == nil then
		-- Wrap around to the beginning of the schedule
		next_delay = frames[1][1] - current_minutes
		if next_delay < 0 then
			next_delay = next_delay + 24 * 60
		end

		-- Use default theme
		theme_name = opts.default.theme
		bg_name = opts.default.bg
	else
		-- Get details of next theme
		theme_name = frames[i][3]
		bg_name = frames[i][4] or opts.default.bg

		-- Adjust start time of next timeframe
		if next_delay == 0 and i < #frames then
			local next_frame = frames[i + 1]
			local adjusted_start = next_frame[1]
			next_delay = (adjusted_start - frames[i][2]) % (24 * 60)
		end
	end

	return { theme = theme_name, bg = bg_name, delay = next_delay }
end

return theme
