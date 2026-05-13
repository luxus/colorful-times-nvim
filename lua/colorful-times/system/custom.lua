-- lua/colorful-times/system/custom.lua

local M = {}

local VALID_BACKGROUNDS = { light = true, dark = true }

local function is_non_empty_string(value)
  return type(value) == "string" and value ~= ""
end

---@param value unknown
---@return string?
---@return string[]?
---@return string?
function M.parse_command(value)
  if type(value) ~= "table" then
    return nil, nil, nil
  end

  local cmd = value[1]
  if not is_non_empty_string(cmd) then
    return nil, nil, "custom detection command must start with a non-empty executable name"
  end

  local args = {}
  for idx = 2, #value do
    if type(value[idx]) ~= "string" then
      return nil, nil, "custom detection command arguments must be strings"
    end
    args[#args + 1] = value[idx]
  end

  return cmd, args, nil
end

function M.plan(cfg)
  if type(cfg.system_background_detection) == "function" then
    return {
      available = true,
      backend = "function",
      detail = "custom Lua function override",
      kind = "function",
      fn = cfg.system_background_detection,
    }
  end

  if type(cfg.system_background_detection) == "table" then
    local cmd, args, err = M.parse_command(cfg.system_background_detection)
    if cmd then
      return {
        available = true,
        backend = "command",
        detail = "custom command override",
        kind = "command_exit_code",
        cmd = cmd,
        args = args,
      }
    end

    return {
      available = false,
      backend = "command",
      detail = "custom command override is invalid",
      kind = "unavailable",
      error = err or "invalid custom detection command",
    }
  end

  return nil
end

function M.run_function(plan, cb, fallback)
  local ok, bg = pcall(plan.fn)
  if ok and VALID_BACKGROUNDS[bg] then
    vim.schedule(function() cb(bg) end)
    return
  end

  local message = ok and "custom detection function must return 'light' or 'dark'"
    or ("custom detection function failed: " .. tostring(bg))
  vim.notify("colorful-times: " .. message, vim.log.levels.WARN)
  vim.schedule(function() cb(fallback) end)
end

return M
