-- lua/colorful-times/health.lua
local M = {}

---@param dir string
---@return boolean ok
---@return string? error
local function writable_dir_check(dir)
  if vim.fn.isdirectory(dir) ~= 1 and vim.fn.mkdir(dir, "p") ~= 1 then
    return false, "could not create state directory"
  end

  local temp_path = dir .. "/.colorful-times-health-" .. tostring(vim.uv.hrtime())
  local flags = bit.bor(vim.uv.constants.O_WRONLY, vim.uv.constants.O_CREAT, vim.uv.constants.O_EXCL)
  local fd, err = vim.uv.fs_open(temp_path, flags, tonumber("600", 8))
  if not fd then
    return false, err or "could not open temporary file"
  end

  local ok = vim.uv.fs_write(fd, "", 0)
  vim.uv.fs_close(fd)
  vim.uv.fs_unlink(temp_path)

  if not ok then
    return false, "could not write temporary file"
  end

  return true
end

---@param health table
local function check_neovim(health)
  -- Neovim version check
  if vim.fn.has("nvim-0.12") == 1 then
    health.ok("Neovim >= 0.12")
  else
    health.error("Neovim >= 0.12 required (found " .. tostring(vim.version()) .. ")")
  end

  -- vim.uv availability
  if vim.uv then
    health.ok("vim.uv available")
  else
    health.error("vim.uv not available — this should not happen on Neovim 0.12+")
  end
end

---@param health table
local function check_dependencies(health)
  -- snacks.nvim (optional)
  local has_snacks = pcall(require, "snacks")
  if has_snacks then
    health.ok("snacks.nvim found (TUI fully functional)")
  else
    health.info("snacks.nvim not found — TUI will use vim.ui.input / vim.ui.select fallback")
  end
end

---@param health table
local function check_state(health)
  -- State file
  local state = require("colorful-times.state")
  local path = state.path()
  local dir = vim.fn.fnamemodify(path, ":h")
  local writable, write_err = writable_dir_check(dir)
  if writable then
    health.ok("State directory writable: " .. dir)
  else
    health.warn("State directory not writable: " .. dir .. " (" .. tostring(write_err) .. ")")
  end
end

---@param health table
local function check_detection(health)
  -- Detection backend
  local system = require("colorful-times.system")
  local detection = system.detection_info()
  if detection.available then
    health.ok("System detection available: " .. detection.detail)
  else
    health.warn("System detection unavailable: " .. detection.detail)
  end
end

---@param health table
local function check_schedule(health)
  -- Schedule validation
  local M_cfg = require("colorful-times")
  local sched = require("colorful-times.schedule")
  local bad = 0
  for idx, entry in ipairs(M_cfg.config.schedule) do
    local ok, err = sched.validate_entry(entry)
    if not ok then
      health.warn(string.format("Schedule entry %d is invalid: %s", idx, err))
      bad = bad + 1
    end
  end
  if bad == 0 then
    health.ok(string.format("Schedule: %d entries, all valid", #M_cfg.config.schedule))
  end
end

---@param health table
local function check_colorscheme(health)
  -- Current colorscheme
  local cs = vim.g.colors_name or "(none)"
  health.info("Current colorscheme: " .. cs)
end

---@return nil
function M.check()
  local health = vim.health

  check_neovim(health)
  check_dependencies(health)
  check_state(health)
  check_detection(health)
  check_schedule(health)
  check_colorscheme(health)
end

return M
