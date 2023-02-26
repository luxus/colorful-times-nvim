local M = {}

--- Sorts an array of timeframes by their start time and fills any gaps between them.
--- @param timeframes table[] A table of timeframes to sort and fill.
--- @return table[] A new table of sorted and filled timeframes.
function M.build_timeframes(timeframes)
	-- Sort the timeframes by their start time.
	table.sort(timeframes, function(a, b)
		return a.start < b.start
	end)

	-- Initialize the new table of timeframes.
	local result = {}

	-- Loop through each timeframe, and add it to the new table.
	for i, tf in ipairs(timeframes) do
		-- Add this timeframe to the result table.
		table.insert(result, tf)

		-- Fill any gap between this timeframe and the previous one.
		local prev_tf = result[i - 1]
		if prev_tf then
			local prev_stop_hour, prev_stop_min = prev_tf.stop:match("(%d+):(%d+)")
			local start_hour, start_min = tf.start:match("(%d+):(%d+)")

			-- Calculate the duration between the two timeframes.
			local duration = (tonumber(start_hour) - tonumber(prev_stop_hour)) * 60
				+ (tonumber(start_min) - tonumber(prev_stop_min))

			if duration > 0 then
				-- Create a new timeframe to fill the gap.
				local filler_tf = {
					start = prev_tf.stop,
					stop = tf.start,
					theme = prev_tf.theme,
					bg = prev_tf.bg,
				}

				-- Add the filler timeframe to the result table.
				table.insert(result, filler_tf)
			end
		end
	end

	return result
end

return M
