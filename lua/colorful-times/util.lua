local M = {}

---Returns true if t1 is before or equal to t2, false otherwise.
---@param t1 table: A table representing a time, with keys "hour" and "min".
---@param t2 table: A table representing a time, with keys "hour" and "min".
---@return boolean: Whether or not t1 is before or equal to t2.
function M.is_time_before_or_equal(t1, t2)
	if t1.hour < t2.hour then
		return true
	elseif t1.hour == t2.hour and t1.min <= t2.min then
		return true
	else
		return false
	end
end

---Returns the number of minutes since midnight for a given time table.
---@param t table: A table representing a time, with keys "hour" and "min".
---@return number: The number of minutes since midnight for the given time.
function M.get_minutes_since_midnight(t)
	return t.hour * 60 + t.min
end

---Returns a table representing the current time.
---@return table: A table representing the current time, with keys "hour" and "min".
function M.get_current_time()
	local current_time = os.date("*t")
	return { hour = current_time.hour, min = current_time.min }
end

return M
