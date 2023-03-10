local time = {}

function time.get()
	-- get the time in 24:00 formatted
	return os.date("%H:%M")
end

function time.in_minutes(formatted_time)
	-- get the time in minutes since midnight
	local hours, minutes = formatted_time:match("(%d+):(%d+)")
	return tonumber(hours) * 60 + tonumber(minutes)
end

return time
