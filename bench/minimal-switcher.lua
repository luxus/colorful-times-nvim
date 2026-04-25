local M = {}
local MINUTES_PER_DAY = 1440
local cfg, parsed = {}, {}
local function parse(s)
  local h, m = s:match("^(%d%d?):(%d%d)$")
  return tonumber(h) * 60 + tonumber(m)
end
local function in_range(e, now)
  local start, stop = e.start, e.stop
  if stop <= start then
    if now < start then now = now + MINUTES_PER_DAY end
    stop = stop + MINUTES_PER_DAY
  end
  return now >= start and now < stop
end
function M.setup(opts)
  cfg = opts or {}
  parsed = {}
  for _, e in ipairs(cfg.schedule or {}) do
    parsed[#parsed + 1] = {
      start = parse(e.start),
      stop = parse(e.stop),
      colorscheme = e.colorscheme,
      background = e.background or (cfg.default and cfg.default.background) or "dark",
    }
  end
end
function M.resolve(now)
  now = now or 720
  local default = cfg.default or {}
  local cs = default.colorscheme or "default"
  local bg = default.background or "dark"
  for _, e in ipairs(parsed) do
    if in_range(e, now) then
      return e.colorscheme, e.background
    end
  end
  return cs, bg
end
function M.apply(now)
  local cs, bg = M.resolve(now)
  vim.o.background = bg
  pcall(vim.cmd.colorscheme, cs)
end
return M
