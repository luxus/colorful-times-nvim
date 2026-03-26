-- lua/colorful-times/state.lua
local M = {}

---@return string
function M.path()
  return vim.fn.stdpath("data") .. "/colorful-times/state.json"
end

---@return table
function M.load()
  local path = M.path()
  local f = io.open(path, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then return {} end
  local ok, result = pcall(vim.json.decode, content)
  if not ok or type(result) ~= "table" then
    vim.notify(
      "colorful-times: failed to parse state file: " .. path,
      vim.log.levels.WARN
    )
    return {}
  end
  return result
end

---@param data table
function M.save(data)
  local path = M.path()
  local dir  = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  local f = io.open(path, "w")
  if not f then
    vim.notify(
      "colorful-times: could not write state file: " .. path,
      vim.log.levels.WARN
    )
    return
  end
  f:write(vim.json.encode(data))
  f:close()
end

---@param base_config table
---@param stored table
---@return table
function M.merge(base_config, stored)
  local result = vim.deepcopy(base_config)
  -- Only override keys that are explicitly present in stored
  if stored.schedule ~= nil then
    result.schedule = stored.schedule
  end
  if stored.enabled ~= nil then
    result.enabled = stored.enabled
  end
  return result
end

return M
