local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local uv = vim.uv
local unpack = table.unpack or unpack
local samples = tonumber(vim.env.CT_BENCH_SAMPLES or "41")
local startup_iters = tonumber(vim.env.CT_BENCH_STARTUP_ITERS or "1")
local apply_iters = tonumber(vim.env.CT_BENCH_APPLY_ITERS or "2000")
local command_iters = tonumber(vim.env.CT_BENCH_COMMAND_ITERS or "1")
local resolve_iters = tonumber(vim.env.CT_BENCH_RESOLVE_ITERS or "50000")
local warmup = tonumber(vim.env.CT_BENCH_WARMUP or "5")

local orig_notify = vim.notify
local orig_defer_fn = vim.defer_fn
local orig_schedule = vim.schedule
local orig_os_date = os.date
vim.notify = function() end
vim.defer_fn = function() end
local fake_min = 720
local function advance_min()
  fake_min = (fake_min + 1) % 1440
  return fake_min
end
rawset(os, "date", function()
  local mins = advance_min()
  return { hour = math.floor(mins / 60), min = mins % 60 }
end)

local sink = 0

local function hourly_schedule()
  local schedule = {}
  for hour = 0, 23 do
    schedule[#schedule + 1] = {
      start = string.format("%02d:00", hour),
      stop = string.format("%02d:00", (hour + 1) % 24),
      colorscheme = "default",
      background = hour >= 7 and hour < 19 and "light" or "dark",
    }
  end
  return schedule
end

local scenarios = {
  {
    enabled = true,
    persist = false,
    default = { colorscheme = "default", background = "dark", themes = { light = "default", dark = "default" } },
    schedule = {},
  },
  {
    enabled = true,
    persist = false,
    default = { colorscheme = "default", background = "dark", themes = { light = "default", dark = "default" } },
    schedule = {
      { start = "08:00", stop = "18:00", colorscheme = "default", background = "light" },
      { start = "18:00", stop = "08:00", colorscheme = "default", background = "dark" },
    },
  },
  {
    enabled = false,
    persist = false,
    default = { colorscheme = "default", background = "light", themes = { light = "default", dark = "default" } },
    schedule = {
      { start = "09:00", stop = "17:00", colorscheme = "default", background = "light" },
    },
  },
  {
    enabled = true,
    persist = false,
    default = { colorscheme = "default", background = "dark", themes = { light = "default", dark = "default" } },
    schedule = hourly_schedule(),
  },
}

local ct_modules = {
  "colorful-times",
  "colorful-times.core",
  "colorful-times.schedule",
  "colorful-times.state",
  "colorful-times.system",
}

local commands = {
  "ColorfulTimes",
  "ColorfulTimesEnable",
  "ColorfulTimesDisable",
  "ColorfulTimesToggle",
  "ColorfulTimesReload",
  "ColorfulTimesStatus",
}

local function clear_ct()
  for _, name in ipairs(ct_modules) do
    package.loaded[name] = nil
  end
end

local function clear_minimal()
  package.loaded["bench.minimal-switcher"] = nil
end

local function now_us()
  return uv.hrtime() / 1000
end

local function median(values)
  table.sort(values)
  local n = #values
  if n % 2 == 1 then
    return values[(n + 1) / 2]
  end
  return (values[n / 2] + values[n / 2 + 1]) / 2
end

local function collect(fn)
  local values = {}
  for _ = 1, warmup do
    fn()
  end
  for i = 1, samples do
    values[i] = fn()
  end
  return median(values)
end

local function ct_startup_once()
  local total = 0
  for _ = 1, startup_iters do
    for _, opts in ipairs(scenarios) do
      clear_ct()
      local t0 = now_us()
      require("colorful-times").setup(opts)
      total = total + (now_us() - t0)
    end
  end
  clear_ct()
  return total / (#scenarios * startup_iters)
end

local function minimal_startup_once()
  local total = 0
  for _ = 1, startup_iters do
    for _, opts in ipairs(scenarios) do
      clear_minimal()
      local t0 = now_us()
      require("bench.minimal-switcher").setup(opts)
      total = total + (now_us() - t0)
    end
  end
  clear_minimal()
  return total / (#scenarios * startup_iters)
end

local function collect_startup_pair()
  local ct_values, minimal_values, delta_values = {}, {}, {}
  for _ = 1, warmup do
    ct_startup_once()
    minimal_startup_once()
  end
  for i = 1, samples do
    ct_values[i] = ct_startup_once()
    minimal_values[i] = minimal_startup_once()
    delta_values[i] = ct_values[i] - minimal_values[i]
  end
  return median(delta_values), median(ct_values), median(minimal_values)
end

local function setup_ct(opts)
  clear_ct()
  local ct = require("colorful-times")
  ct.setup(opts)
  return ct
end

local function setup_minimal(opts)
  clear_minimal()
  local mini = require("bench.minimal-switcher")
  mini.setup(opts)
  return mini
end

local function ct_resolve_once()
  local total = 0
  for _, opts in ipairs(scenarios) do
    local ct = setup_ct(opts)
    local t0 = now_us()
    for _ = 1, resolve_iters do
      local cs, bg = ct.resolve_theme()
      sink = sink + #cs + #bg
    end
    total = total + (now_us() - t0) / resolve_iters
  end
  clear_ct()
  return total / #scenarios
end

local function minimal_resolve_once()
  local total = 0
  for _, opts in ipairs(scenarios) do
    local mini = setup_minimal(opts)
    local t0 = now_us()
    for _ = 1, resolve_iters do
      local cs, bg = mini.resolve(advance_min())
      sink = sink + #cs + #bg
    end
    total = total + (now_us() - t0) / resolve_iters
  end
  clear_minimal()
  return total / #scenarios
end

local function ct_apply_once()
  vim.schedule = function(fn) fn() end
  local total = 0
  for _, opts in ipairs(scenarios) do
    local ct = setup_ct(opts)
    local t0 = now_us()
    for _ = 1, apply_iters do
      ct.apply_colorscheme()
    end
    total = total + (now_us() - t0) / apply_iters
  end
  vim.schedule = orig_schedule
  clear_ct()
  return total / #scenarios
end

local function minimal_apply_once()
  local total = 0
  for _, opts in ipairs(scenarios) do
    local mini = setup_minimal(opts)
    local t0 = now_us()
    for _ = 1, apply_iters do
      mini.apply(advance_min())
    end
    total = total + (now_us() - t0) / apply_iters
  end
  clear_minimal()
  return total / #scenarios
end

local function collect_apply_pair()
  local ct_values, minimal_values, delta_values = {}, {}, {}
  for _ = 1, warmup do
    ct_apply_once()
    minimal_apply_once()
  end
  for i = 1, samples do
    ct_values[i] = ct_apply_once()
    minimal_values[i] = minimal_apply_once()
    delta_values[i] = ct_values[i] - minimal_values[i]
  end
  return median(delta_values), median(ct_values), median(minimal_values)
end

local function command_once()
  local total = 0
  for _ = 1, command_iters do
    for _, cmd in ipairs(commands) do
      pcall(vim.api.nvim_del_user_command, cmd)
    end
    local t0 = now_us()
    vim.cmd.runtime("plugin/colorful-times.lua")
    total = total + (now_us() - t0)
  end
  for _, cmd in ipairs(commands) do
    pcall(vim.api.nvim_del_user_command, cmd)
  end
  return total / command_iters
end

local delta_us, ct_startup_us, minimal_startup_us = collect_startup_pair()
local ct_resolve_us = collect(ct_resolve_once)
local minimal_resolve_us = collect(minimal_resolve_once)
local apply_delta_us, ct_apply_us, minimal_apply_us = collect_apply_pair()
local command_us = collect(command_once)
local ratio_x = ct_startup_us / minimal_startup_us
local resolve_delta_us = ct_resolve_us - minimal_resolve_us

local metrics = {
  { "delta_us", delta_us },
  { "ct_startup_us", ct_startup_us },
  { "minimal_startup_us", minimal_startup_us },
  { "startup_ratio_x", ratio_x },
  { "ct_resolve_us", ct_resolve_us },
  { "minimal_resolve_us", minimal_resolve_us },
  { "resolve_delta_us", resolve_delta_us },
  { "ct_apply_us", ct_apply_us },
  { "minimal_apply_us", minimal_apply_us },
  { "apply_delta_us", apply_delta_us },
  { "command_us", command_us },
}

for _, item in ipairs(metrics) do
  print(string.format("METRIC %s=%.6f", item[1], item[2]))
end
vim.g.ct_bench_sink = sink

vim.notify = orig_notify
vim.defer_fn = orig_defer_fn
vim.schedule = orig_schedule
rawset(os, "date", orig_os_date)
clear_ct()
clear_minimal()
