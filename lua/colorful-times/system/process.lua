-- lua/colorful-times/system/process.lua
-- Process adapter for system background detection plans.

local M = {}
local uv = vim.uv

---@param cmd string
---@param args string[]
---@param callback fun(code: integer|nil, stdout: string, stderr: string)
function M.spawn_capture(cmd, args, callback)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local out, err = {}, {}

  local handle
  handle = uv.spawn(cmd, { args = args, stdio = { nil, stdout, stderr } }, function(code)
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()
    if handle and not handle:is_closing() then
      handle:close()
    end
    callback(code, table.concat(out), table.concat(err))
  end)

  if not handle then
    stdout:close()
    stderr:close()
    callback(nil, "", "spawn failed: " .. cmd)
    return
  end

  stdout:read_start(function(_, data)
    if data then out[#out + 1] = data end
  end)
  stderr:read_start(function(_, data)
    if data then err[#err + 1] = data end
  end)
end

---@param cmd string
---@param args string[]
---@param callback fun(code: integer|nil)
function M.spawn_code(cmd, args, callback)
  M.spawn_capture(cmd, args, function(code)
    callback(code)
  end)
end

return M
