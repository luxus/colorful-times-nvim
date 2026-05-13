-- lua/colorful-times/system.lua
-- System background detection plan selection and execution.

local M = {}

local env_mod
local process_mod
local custom_mod
local darwin_mod
local linux_mod
local _sysname

local function env()
  env_mod = env_mod or require("colorful-times.system.env")
  return env_mod
end

local function process()
  process_mod = process_mod or require("colorful-times.system.process")
  return process_mod
end

local function custom()
  custom_mod = custom_mod or require("colorful-times.system.custom")
  return custom_mod
end

local function darwin()
  darwin_mod = darwin_mod or require("colorful-times.system.darwin")
  return darwin_mod
end

local function linux()
  linux_mod = linux_mod or require("colorful-times.system.linux")
  return linux_mod
end

---@return string
function M.sysname()
  _sysname = _sysname or env().sysname()
  return _sysname
end

---@class ColorfulTimes.DetectionInfo
---@field available boolean
---@field backend string
---@field detail string

---@class ColorfulTimes.DetectionPlan
---@field available boolean
---@field backend string
---@field detail string
---@field kind string
---@field cmd string|nil
---@field args string[]|nil
---@field dark_pattern string|nil
---@field fn function|nil
---@field error string|nil

---@return ColorfulTimes.DetectionPlan
function M.detection_plan()
  local cfg = require("colorful-times").config
  local override = custom().plan(cfg)
  if override then
    return override
  end

  local sysname = M.sysname()
  if sysname == "Darwin" then
    return darwin().plan()
  end

  if sysname == "Linux" then
    return linux().plan(cfg, env())
  end

  return {
    available = false,
    backend = "unsupported",
    detail = "platform is unsupported for automatic detection",
    kind = "unavailable",
  }
end

---@return ColorfulTimes.DetectionInfo
function M.detection_info()
  local plan = M.detection_plan()
  return {
    available = plan.available,
    backend = plan.backend,
    detail = plan.detail,
  }
end

---@return boolean
function M.has_detection()
  return M.detection_plan().available
end

---@param plan ColorfulTimes.DetectionPlan
---@param cb fun(bg: "light"|"dark")
---@param fallback "light"|"dark"
function M.run_detection_plan(plan, cb, fallback)
  fallback = fallback == "light" and "light" or "dark"

  if not plan or not plan.available then
    if plan and plan.error then
      vim.notify("colorful-times: " .. plan.error, vim.log.levels.WARN)
    end
    vim.schedule(function() cb(fallback) end)
    return
  end

  if plan.kind == "function" then
    custom().run_function(plan, cb, fallback)
    return
  end

  if plan.kind == "command_exit_code" then
    process().spawn_code(plan.cmd, plan.args or {}, function(code)
      vim.schedule(function()
        if code == nil then
          vim.notify("colorful-times: detection command failed to start", vim.log.levels.WARN)
          cb(fallback)
          return
        end
        cb(code == 0 and "dark" or "light")
      end)
    end)
    return
  end

  if plan.kind == "command_output_contains" then
    process().spawn_capture(plan.cmd, plan.args or {}, function(code, out)
      local is_dark = code == 0 and out:find(plan.dark_pattern or "", 1, true) ~= nil
      vim.schedule(function() cb(is_dark and "dark" or "light") end)
    end)
    return
  end

  if plan.kind == "darwin_appearance" then
    darwin().run(process(), cb, fallback)
    return
  end

  vim.schedule(function() cb(fallback) end)
end

---@param cb fun(bg: "light"|"dark")
---@param fallback "light"|"dark"
function M.get_background(cb, fallback)
  M.run_detection_plan(M.detection_plan(), cb, fallback)
end

return M
