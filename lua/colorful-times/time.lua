local time = {}

function time.get_time_in_minutes(time_str)
	local hours, mins = time_str:match("(%d+):(%d+)")
	return tonumber(hours) * 60 + tonumber(mins)
end

function time.get_time_diff_in_minutes(start_time_str, end_time_str)
	local start_mins = time.get_time_in_minutes(start_time_str)
	local end_mins = time.get_time_in_minutes(end_time_str)
	return end_mins - start_mins
end

function time.get_current_time_in_minutes()
	local current_time_str = os.date("%H:%M")
	return time.get_time_in_minutes(current_time_str)
end

return time
