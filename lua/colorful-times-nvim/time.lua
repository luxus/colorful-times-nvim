local time = {}

-- use os.date to get the current time in minutes since midnight
function time.get()
	return os.date("*t")
end
function time.convert_24_to_table(formatted_time)
	local hour = tonumber(string.sub(formatted_time, 1, 2))
	local min = tonumber(string.sub(formatted_time, 4, 5))
	return { hour = hour, min = min }
end
-- convert a table representing a time to minutes since midnight
function time.in_minutes(time_table)
	local total_minutes = (time_table.hour * 60) + time_table.min
	return total_minutes
end

return time
