-- Benchmark for next_change_at performance
-- Tests schedule performance with varying entry counts

local schedule = require("colorful-times.schedule")

-- Generate test schedules of different sizes
local function generate_schedule(n)
  local sched = {}
  local interval = math.floor(1440 / n)  -- minutes per entry
  for i = 1, n do
    local start_min = (i - 1) * interval
    local stop_min = (i * interval) % 1440  -- Wrap around at midnight
    table.insert(sched, {
      start = string.format("%02d:%02d", math.floor(start_min / 60), start_min % 60),
      stop = string.format("%02d:%02d", math.floor(stop_min / 60), stop_min % 60),
      colorscheme = "theme" .. i,
    })
  end
  return sched
end

-- Warmup
for _ = 1, 100 do
  local s = generate_schedule(2)
  local p = schedule.preprocess(s, "dark")
  schedule.next_change_at(p, 720)
end

-- Benchmark different sizes
local sizes = {2, 5, 10, 20, 50}
local iterations = 10000

for _, n in ipairs(sizes) do
  local s = generate_schedule(n)
  local p = schedule.preprocess(s, "dark")

  -- Force cache miss each time by varying time
  local start = vim.uv.hrtime()
  for i = 1, iterations do
    schedule.next_change_at(p, (i * 17) % 1440)  -- Vary time to avoid cache hits
  end
  local elapsed = vim.uv.hrtime() - start

  local total_us = elapsed / 1000  -- ns → µs
  local per_call_us = total_us / iterations

  print(string.format("entries=%d total_µs=%.1f per_call_µs=%.3f", n, total_us, per_call_us))
end

-- Print final metric for smallest size (most common case)
local s = generate_schedule(2)
local p = schedule.preprocess(s, "dark")
local start = vim.uv.hrtime()
for i = 1, iterations do
  schedule.next_change_at(p, (i * 17) % 1440)
end
local elapsed = vim.uv.hrtime() - start
local metric_us = elapsed / 1000  -- Total µs for 2 entries

print(string.format("METRIC next_change_at_µs=%.1f", metric_us))
