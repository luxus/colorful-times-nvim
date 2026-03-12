--- Colorful Times Implementation
--- This file contains the implementation details loaded on-demand
--- to reduce the startup impact of the main module.

local M = require("colorful-times")

-- Import vim.loop only when needed
-- Use vim.uv available in Neovim >= 0.10
local uv = vim.uv

-- Cache for parsed schedule times.
---@type ColorfulTimes.ParsedScheduleEntry[]
local parsed_schedule = {}

-- Timer handles
---@type uv_timer_t|nil
local timer
---@type uv_timer_t|nil
local appearance_timer

-- Keep track of the previous system background.
---@type string|nil
local previous_background

-- Function to create timers
local function create_timer()
	return uv.new_timer()
end

-- Function to stop and close timers
local function stop_and_close_timer(timer_handle)
	if timer_handle and not timer_handle:is_closing() then
		timer_handle:stop()
		timer_handle:close()
	end
end

-- Helper function to parse time strings into minutes since midnight.
---@param time_str string Time string in "HH:MM" format.
---@return integer|nil Minutes since midnight or nil if invalid.
local function parse_time(time_str)
	if type(time_str) ~= "string" then
		return nil
	end
	local hour, min = time_str:match("^(%d%d?):(%d%d)$")
	if not hour or not min then
		return nil
	end
	hour = tonumber(hour)
	min = tonumber(min)
	if hour >= 24 or min >= 60 then
		return nil
	end
	return hour * 60 + min
end

-- Pre-process and cache parsed schedule times.
local function preprocess_schedule()
	parsed_schedule = {}
	for idx, slot in ipairs(M.config.schedule) do
		local start_time = parse_time(slot.start)
		local stop_time = parse_time(slot.stop)
		if not start_time or not stop_time then
			vim.api.nvim_err_writeln(string.format("Invalid time format in schedule entry %d", idx))
		else
			local background = slot.background or M.config.default.background
			table.insert(parsed_schedule, {
				start_time = start_time,
				stop_time = stop_time,
				colorscheme = slot.colorscheme,
				background = background,
			})
		end
	end
end

-- Get current time in minutes since midnight.
---@return integer Minutes since midnight.
local function get_current_time()
	local date_table = os.date("*t")
	return (date_table.hour * 60) + date_table.min
end

-- Helper function to detect system background on macOS
---@param handle_spawn_result fun(code: integer) Callback function to handle the spawn result
local function detect_darwin_background(handle_spawn_result)
	local handle
	handle = uv.spawn("defaults", {
		args = { "read", "-g", "AppleInterfaceStyle" },
		stdio = { nil, nil, nil },
	}, function(code, _signal)
		handle:close()
		-- Handle the result of the spawn.
		handle_spawn_result(code)
	end)
end

-- Helper function to detect system background on Linux using custom configuration
---@param callback fun(background: string) Callback function to execute with the background value
---@param fallback string The fallback background value
---@param handle_spawn_result fun(code: integer) Callback function to handle the spawn result
local function detect_linux_custom_background(callback, fallback, handle_spawn_result)
	local background = nil
	if type(M.config.system_background_detection) == "table" then
		-- Execute a custom command safely from a table of arguments.
		local handle
		local cmd = M.config.system_background_detection[1]
		local args = {}
		for i = 2, #M.config.system_background_detection do
			table.insert(args, M.config.system_background_detection[i])
		end
		handle = uv.spawn(cmd, {
			args = args,
			stdio = { nil, nil, nil },
		}, function(code, _signal)
			handle:close()
			-- Handle the result of the spawn.
			handle_spawn_result(code)
		end)
	elseif type(M.config.system_background_detection) == "function" then
		-- Call the user-provided function to detect the background.
		background = M.config.system_background_detection()
		vim.schedule(function()
			callback(background)
		end)
	else
		-- Use the fallback background if detection is not configured.
		vim.schedule(function()
			callback(fallback)
		end)
	end
end

-- Helper function to auto-detect system background on Linux
---@param handle_spawn_result fun(code: integer) Callback function to handle the spawn result
local function detect_linux_auto_background(handle_spawn_result)
	-- Attempt to auto-detect desktop environment without user configuration
	local kde_detection = [[
      if command -v kreadconfig6 &> /dev/null; then
        kreadconfig6 --group 'General' --key 'ColorScheme' --file 'kdeglobals' | grep -q 'Dark' ||
        kreadconfig6 --group 'KDE' --key 'LookAndFeelPackage' | grep -q 'dark'
      elif command -v kreadconfig5 &> /dev/null; then
        kreadconfig5 --group 'General' --key 'ColorScheme' --file 'kdeglobals' | grep -q 'Dark'
      else
        exit 1  # Default to light if commands not available
      fi
    ]]

	local gnome_detection = [[
      if command -v gsettings &> /dev/null; then
        gsettings get org.gnome.desktop.interface color-scheme | grep -q 'prefer-dark'
      else
        exit 1  # Default to light if commands not available
      fi
    ]]

	-- Try to auto-detect desktop environment and dark mode
	local handle
	handle = uv.spawn("sh", {
		args = {
			"-c",
			[[
          # Try KDE detection first
          if [ "$XDG_CURRENT_DESKTOP" = "KDE" ] || [ "$XDG_SESSION_DESKTOP" = "KDE" ]; then
            ]] .. kde_detection .. [[
          # Try GNOME detection
          elif [ "$XDG_CURRENT_DESKTOP" = "GNOME" ] || [ "$XDG_SESSION_DESKTOP" = "GNOME" ]; then
            ]] .. gnome_detection .. [[
          # If we can't determine desktop environment, default to light
          else
            exit 1
          fi
        ]],
		},
		stdio = { nil, nil, nil },
	}, function(code, _signal)
		handle:close()
		-- Handle the result of the spawn.
		handle_spawn_result(code)
	end)
end

-- Function to get the system background.
---@param callback fun(background: string) Callback function to execute with the background value.
---@param fallback string The fallback background value.
local function get_system_background(callback, fallback)
	-- Cache the OS info - only need to get this once
	local sysname = M._cached_sysname or uv.os_uname().sysname or "Unknown"
	M._cached_sysname = sysname

	-- Function to handle the result of the system background command.
	local function handle_spawn_result(code)
		vim.schedule(function()
			if code == 0 then
				callback("dark")
			else
				callback("light")
			end
		end)
	end

	if sysname == "Darwin" then
		detect_darwin_background(handle_spawn_result)
	elseif sysname == "Linux" then
		-- Linux system detection - attempt to auto-detect desktop environment if no custom detection provided
		if M.config.system_background_detection then
			detect_linux_custom_background(callback, fallback, handle_spawn_result)
		else
			detect_linux_auto_background(handle_spawn_result)
		end
	else
		-- Use the fallback background for unsupported operating systems.
		vim.schedule(function()
			callback(fallback)
		end)
	end
end

-- Determine the active colorscheme based on the schedule.
---@return ColorfulTimes.ParsedScheduleEntry|nil The active schedule entry or nil if none matches.
local function get_active_colorscheme()
	local current_time = get_current_time()
	for _, slot in ipairs(parsed_schedule) do
		local start_time = slot.start_time
		local stop_time = slot.stop_time
		local adjusted_current_time = current_time

		-- Handle overnight schedules where stop time is earlier than start time.
		if stop_time <= start_time then
			if current_time < start_time then
				adjusted_current_time = adjusted_current_time + 24 * 60
			end
			stop_time = stop_time + 24 * 60
		end

		-- Check if the current time falls within the schedule slot.
		if adjusted_current_time >= start_time and adjusted_current_time < stop_time then
			return slot
		end
	end

	-- Return nil if no matching schedule slot is found.
	return nil
end

-- Apply the colorscheme.
local function apply_colorscheme()
	-- Internal function to set the colorscheme.
	local function set_colorscheme(background)
		vim.schedule(function()
			-- Update the previous background value.
			previous_background = background
			-- Set the Vim background option.
			vim.o.background = background

			-- Determine the colorscheme based on schedule or default
			local colorscheme = M.config.default.colorscheme
			local from_schedule = false

			-- Determine if a schedule is active and update the colorscheme.
			if M.config.enabled then
				local active_slot = get_active_colorscheme()
				if active_slot then
					colorscheme = active_slot.colorscheme
					from_schedule = true
				end
			end

			-- If not from a schedule and themes are configured for the current background,
			-- use the appropriate theme-specific colorscheme
			if not from_schedule and M.config.default.themes then
				local theme_for_background = M.config.default.themes[background]
				if theme_for_background then
					colorscheme = theme_for_background
				end
			end

			-- Apply the colorscheme and handle any errors.
			local ok, err = pcall(function()
				vim.cmd.colorscheme(colorscheme)
			end)
			if not ok then
				vim.api.nvim_err_writeln("Failed to apply colorscheme '" .. colorscheme .. "': " .. err)
			end
		end)
	end

	-- Determine the background setting.
	local background = M.config.default.background
	if M.config.enabled then
		local active_slot = get_active_colorscheme()
		if active_slot then
			background = active_slot.background
		end
	end

	if background == "system" then
		-- Determine the initial fallback background value.
		local fallback = M.config.default.background ~= "system" and M.config.default.background
			or vim.o.background
			or "dark"

		-- Immediately apply the fallback background to avoid blocking Neovim startup.
		-- This guarantees instant colorscheme application before UI rendering.
		set_colorscheme(fallback)

		-- Query the true system background asynchronously. Only apply if it differs.
		get_system_background(function(bg)
			if previous_background ~= bg then
				set_colorscheme(bg)
			end
		end, fallback)
	else
		-- Apply the colorscheme directly if not using system background.
		set_colorscheme(background)
	end
end

-- Schedule the next colorscheme change.
local function schedule_next_change()
	-- Stop existing timer if any.
	stop_and_close_timer(timer)
	timer = nil

	-- Return early if the plugin is disabled.
	if not M.config.enabled then
		return
	end

	-- Get the current time in minutes since midnight.
	local current_time = get_current_time()
	local min_diff = 24 * 60 -- Maximum possible difference.
	local next_change_in = nil

	-- Iterate over the parsed schedule to determine the next change.
	for _, slot in ipairs(parsed_schedule) do
		-- Process start_time and stop_time separately to avoid table allocation.
		local start_time = slot.start_time
		local stop_time = slot.stop_time

		-- Check start time
		local adj_start = start_time
		if start_time <= current_time then
			adj_start = adj_start + 24 * 60
		end
		local diff_start = adj_start - current_time
		if diff_start > 0 and diff_start < min_diff then
			min_diff = diff_start
			next_change_in = diff_start
		end

		-- Check stop time
		local adj_stop = stop_time
		if stop_time <= current_time then
			adj_stop = adj_stop + 24 * 60
		end
		local diff_stop = adj_stop - current_time
		if diff_stop > 0 and diff_stop < min_diff then
			min_diff = diff_stop
			next_change_in = diff_stop
		end
	end

	-- Schedule the next colorscheme change if applicable.
	if next_change_in then
		timer = create_timer()
		timer:start(next_change_in * 60 * 1000, 0, function()
			vim.schedule(function()
				apply_colorscheme()
				schedule_next_change()
			end)
		end)
	end
end

-- Start a timer to periodically check the system appearance.
local function start_system_appearance_timer()
	-- Stop and close any existing appearance timer.
	stop_and_close_timer(appearance_timer)
	appearance_timer = nil

	-- Use cached OS info to avoid expensive calls
	local sysname = M._cached_sysname or uv.os_uname().sysname or "Unknown"
	M._cached_sysname = sysname
	if sysname ~= "Darwin" and sysname ~= "Linux" then
		-- Only macOS and Linux are supported for system appearance detection.
		return
	end

	-- Compute fallback background value.
	local fallback = previous_background
		or M.config.default.background ~= "system" and M.config.default.background
		or vim.o.background
		or "dark"

	-- Create a new timer to check the system appearance.
	appearance_timer = create_timer()
	appearance_timer:start(0, M.config.refresh_time, function()
		-- Determine if we even need to poll the system
		local active_background = M.config.default.background
		if M.config.enabled then
			local active_slot = get_active_colorscheme()
			if active_slot then
				active_background = active_slot.background
			end
		end

		-- Only spawn processes if we actually care about the system background
		if active_background == "system" then
			-- Get the system background periodically and apply the colorscheme if it changes.
			get_system_background(function(current_background)
				if current_background ~= previous_background then
					apply_colorscheme()
				end
			end, fallback)
		end
	end)
end

-- Helper function to enable the plugin.
local function enable_plugin()
	-- If enabled, apply the colorscheme and schedule changes.
	apply_colorscheme()
	schedule_next_change()
	start_system_appearance_timer()
	vim.notify("Colorful Times enabled.", vim.log.levels.INFO)
end

-- Helper function to disable the plugin.
local function disable_plugin()
	-- If disabled, stop timers and apply default colorscheme.
	stop_and_close_timer(timer)
	timer = nil
	stop_and_close_timer(appearance_timer)
	appearance_timer = nil
	-- Apply the default colorscheme and background.
	local background = M.config.default.background
	if background == "system" then
		-- Compute fallback background value.
		local fallback = M.config.default.background ~= "system" and M.config.default.background
			or vim.o.background
			or "dark"

		-- Immediately apply fallback default colorscheme
		previous_background = fallback
		vim.o.background = fallback

		local fallback_colorscheme = M.config.default.colorscheme
		if M.config.default.themes and M.config.default.themes[fallback] then
			fallback_colorscheme = M.config.default.themes[fallback]
		end
		pcall(function()
			vim.cmd.colorscheme(fallback_colorscheme)
		end)

		-- Get the system background and apply the default colorscheme if it differs
		get_system_background(function(bg)
			if bg ~= fallback then
				previous_background = bg
				vim.schedule(function()
					vim.o.background = bg

					-- Determine which colorscheme to use based on background
					local colorscheme = M.config.default.colorscheme
					if M.config.default.themes and M.config.default.themes[bg] then
						colorscheme = M.config.default.themes[bg]
					end

					pcall(function()
						vim.cmd.colorscheme(colorscheme)
					end)
				end)
			end
		end, fallback)
	else
		-- Apply the default colorscheme directly.
		previous_background = background
		vim.o.background = background

		-- Determine which colorscheme to use based on background
		local colorscheme = M.config.default.colorscheme
		if M.config.default.themes and M.config.default.themes[background] then
			colorscheme = M.config.default.themes[background]
		end

		pcall(function()
			vim.cmd.colorscheme(colorscheme)
		end)
	end
	vim.notify("Colorful Times disabled.", vim.log.levels.INFO)
end

-- Reload the plugin configuration.
function M.reload()
	-- Re-initialize the plugin with the current configuration.
	M.setup(M.config)
end

-- Toggle the plugin on or off.
function M.toggle()
	-- Toggle the enabled state of the plugin.
	M.config.enabled = not M.config.enabled
	if M.config.enabled then
		enable_plugin()
	else
		disable_plugin()
	end
end

-- Setup function to configure the plugin.
---@param opts ColorfulTimes.Config Configuration options provided by the user.
function M.setup(opts)
	-- Merge user-provided options with the default configuration more efficiently
	if opts then
		-- Only deep merge if there are nested tables that need merging
		if opts.default then
			M.config.default = vim.tbl_deep_extend("force", M.config.default, opts.default)
			opts.default = nil
		end
		-- For the rest, just do a shallow merge
		for k, v in pairs(opts) do
			M.config[k] = v
		end
	end

	-- Pre-process the schedule based on the updated configuration.
	preprocess_schedule()

	-- Try to get background synchronously on startup if possible
	-- so it applies instantly before Neovim reveals the UI
	apply_colorscheme()

	-- Start timers asynchronously
	schedule_next_change()
	start_system_appearance_timer()
end

-- Make functions visible for tests but not exported to users
-- These should only be available in impl module
M.parse_time = parse_time
M.preprocess_schedule = preprocess_schedule
M.get_system_background = get_system_background
M.detect_darwin_background = detect_darwin_background
M.detect_linux_custom_background = detect_linux_custom_background
M.detect_linux_auto_background = detect_linux_auto_background
M.get_active_colorscheme = get_active_colorscheme
M.apply_colorscheme = apply_colorscheme
M.get_parsed_schedule = function()
	return parsed_schedule
end
M.get_current_time = get_current_time

return M
