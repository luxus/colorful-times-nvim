local time = {}

function time.get()
	-- get the time in 24:00 formatted, using only the current start time
	local start_time = os.date("%H:%M", os.time())
	return start_time
end

function time.in_minutes(formatted_time)
	-- get the time in minutes since midnight, using only the start time
	local hours, minutes = formatted_time:match("(%d+):(%d+)")
	return tonumber(hours) * 60 + tonumber(minutes)
end

return time
