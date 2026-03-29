-- Startup benchmark for colorful-times
local function benchmark()
  -- Clear all caches and reload
  for name in pairs(package.loaded) do
    if name:match("^colorful%-times") then
      package.loaded[name] = nil
    end
  end

  -- Collect garbage to get clean state
  collectgarbage("collect")
  collectgarbage("collect")

  -- Measure require time
  local uv = vim.uv
  local start = uv.hrtime()

  local ct = require("colorful-times")

  -- Measure setup time
  local setup_start = uv.hrtime()
  ct.setup({
    enabled = true,
    refresh_time = 5000,
    default = {
      colorscheme = "default",
      background = "dark",
      themes = { light = nil, dark = nil },
    },
    schedule = {
      { start = "08:00", stop = "18:00", colorscheme = "morning", background = "light" },
      { start = "18:00", stop = "08:00", colorscheme = "evening", background = "dark" },
    },
    persist = true,
  })
  local end_time = uv.hrtime()

  local require_time = (setup_start - start) / 1e6  -- ms
  local setup_time = (end_time - setup_start) / 1e6  -- ms
  local total_time = (end_time - start) / 1e6  -- ms

  -- Output metrics
  print(string.format("METRIC require_ms=%.4f", require_time))
  print(string.format("METRIC setup_ms=%.4f", setup_time))
  print(string.format("METRIC total_ms=%.4f", total_time))

  return total_time
end

-- Run benchmark
benchmark()

-- Exit
vim.cmd("qa!")
