-- lua/colorful-times/schedule.lua
local M = {}

---@param str string
---@return integer|nil
function M.parse_time(str)
	local hour, min = str:match("^(%d%d?):(%d%d)$")
	if not hour then
		return nil
	end
	hour, min = tonumber(hour), tonumber(min)
	if hour >= 24 or min >= 60 then
		return nil
	end
	return hour * 60 + min
end

---@param entry table
---@return boolean, string?
function M.validate_entry(entry)
	if not entry.colorscheme or entry.colorscheme == "" then
		return false, "missing colorscheme"
	end
	if not M.parse_time(entry.start or "") then
		return false, "invalid start time: " .. tostring(entry.start)
	end
	if not M.parse_time(entry.stop or "") then
		return false, "invalid stop time: " .. tostring(entry.stop)
	end
	if entry.background and not vim.tbl_contains({ "light", "dark", "system" }, entry.background) then
		return false, "invalid background: " .. entry.background .. " (must be light, dark, or system)"
	end
	return true
end

---@param raw_schedule table
---@param default_background string
---@return ColorfulTimes.ParsedEntry[]
function M.preprocess(raw_schedule, default_background)
	local result = {}
	for idx, slot in ipairs(raw_schedule) do
		local ok, err = M.validate_entry(slot)
		if not ok then
			vim.notify(string.format("colorful-times: invalid schedule entry %d: %s", idx, err), vim.log.levels.ERROR)
		else
			table.insert(result, {
				start_time = M.parse_time(slot.start),
				stop_time = M.parse_time(slot.stop),
				colorscheme = slot.colorscheme,
				background = slot.background or default_background,
			})
		end
	end
	return result
end

---@param parsed ColorfulTimes.ParsedEntry[]
---@param time_mins integer
---@return ColorfulTimes.ParsedEntry|nil
function M.get_active_entry(parsed, time_mins)
	for _, slot in ipairs(parsed) do
		local start_t = slot.start_time
		local stop_t = slot.stop_time
		local current = time_mins

		if stop_t <= start_t then
			-- overnight: e.g. 22:00 -> 06:00
			if current < start_t then
				current = current + 1440
			end
			stop_t = stop_t + 1440
		end

		if current >= start_t and current < stop_t then
			return slot
		end
	end
	return nil
end

---@param parsed ColorfulTimes.ParsedEntry[]
---@param time_mins integer
---@return integer|nil
function M.next_change_at(parsed, time_mins)
	if #parsed == 0 then
		return nil
	end
	local min_diff = nil

	for i = 1, #parsed do
		local slot = parsed[i]

		-- Check start_time boundary
		local diff_start = slot.start_time - time_mins
		if diff_start <= 0 then
			diff_start = diff_start + 1440
		end
		if not min_diff or diff_start < min_diff then
			min_diff = diff_start
		end

		-- Check stop_time boundary
		local diff_stop = slot.stop_time - time_mins
		if diff_stop <= 0 then
			diff_stop = diff_stop + 1440
		end
		if not min_diff or diff_stop < min_diff then
			min_diff = diff_stop
		end
	end

	return min_diff
end

return M
