# colorful-times v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full rewrite of colorful-times.nvim for Neovim 0.12+, splitting the monolithic `impl.lua` into focused modules, adding a snacks-powered TUI for schedule management, and persisting TUI changes to disk.

**Architecture:** Seven focused modules (`init`, `schedule`, `system`, `state`, `core`, `tui`, `health`) plus a thin `plugin/` entry point. All modules are lazy-loaded. `schedule.lua` is pure Lua with no side effects, enabling fast isolated testing. `core.lua` owns all mutable timer state. `tui.lua` depends on snacks.nvim (optional) with graceful fallback to `vim.ui.*`.

**Tech Stack:** Lua (LuaJIT via Neovim 0.12), `vim.uv`, snacks.nvim (optional), plenary.nvim (tests), vim.health, vim.json

---

## File Map

| File | Status | Responsibility |
|------|--------|----------------|
| `lua/colorful-times/init.lua` | Rewrite | Config defaults, metatable lazy-loader, type annotations only |
| `lua/colorful-times/schedule.lua` | Create | Pure parse/validate/match functions |
| `lua/colorful-times/system.lua` | Create | Async OS dark/light detection |
| `lua/colorful-times/state.lua` | Create | JSON persistence (load/save/merge) |
| `lua/colorful-times/core.lua` | Create | State machine, timers, apply_colorscheme |
| `lua/colorful-times/tui.lua` | Create | Table Manager TUI (snacks + fallback) |
| `lua/colorful-times/health.lua` | Create | `:checkhealth colorful-times` |
| `plugin/colorful-times.lua` | Create | Registers vim commands at startup |
| `lua/colorful-times/impl.lua` | Delete | Replaced by the modules above |
| `tests/schedule_spec.lua` | Create | Unit tests for schedule.lua |
| `tests/system_spec.lua` | Create | Unit tests for system.lua |
| `tests/state_spec.lua` | Create | Unit tests for state.lua |
| `tests/core_spec.lua` | Create | Unit tests for core.lua |
| `tests/colorful_times_spec.lua` | Delete | Replaced by per-module specs |
| `tests/minimal_init.vim` | Update | Add snacks.nvim stub path |
| `.github/README.md` | Update | Reflect new requirements and TUI docs |
| `doc/colorful-times.txt` | Update | Reflect new API and commands |
| `.github/workflows/ci.yml` | Update | Drop Lua version matrix, keep nvim stable+nightly |

---

## Task 1: Scaffold `schedule.lua` with tests (TDD)

This is the foundation. Pure functions, no Neovim deps beyond `vim.notify`. Build test-first.

**Files:**
- Create: `lua/colorful-times/schedule.lua`
- Create: `tests/schedule_spec.lua`

- [ ] **Step 1: Create the test file**

```lua
-- tests/schedule_spec.lua
local schedule = require("colorful-times.schedule")

describe("schedule.parse_time", function()
  it("parses valid HH:MM", function()
    assert.are.equal(0,    schedule.parse_time("00:00"))
    assert.are.equal(60,   schedule.parse_time("01:00"))
    assert.are.equal(1439, schedule.parse_time("23:59"))
    assert.are.equal(690,  schedule.parse_time("11:30"))
  end)

  it("returns nil for invalid input", function()
    assert.is_nil(schedule.parse_time("24:00"))
    assert.is_nil(schedule.parse_time("12:60"))
    assert.is_nil(schedule.parse_time("invalid"))
    assert.is_nil(schedule.parse_time(""))
    assert.is_nil(schedule.parse_time("1:00"))   -- single-digit hour ok
    assert.are.equal(60, schedule.parse_time("1:00"))  -- actually valid per spec
  end)
end)

describe("schedule.validate_entry", function()
  it("accepts a fully valid entry", function()
    local ok, err = schedule.validate_entry({
      start = "08:00", stop = "18:00",
      colorscheme = "tokyonight", background = "dark",
    })
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("accepts entry without background (optional)", function()
    local ok, err = schedule.validate_entry({
      start = "08:00", stop = "18:00", colorscheme = "tokyonight",
    })
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("rejects entry with invalid start time", function()
    local ok, err = schedule.validate_entry({
      start = "25:00", stop = "18:00", colorscheme = "tokyonight",
    })
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("rejects entry with invalid stop time", function()
    local ok, err = schedule.validate_entry({
      start = "08:00", stop = "60:00", colorscheme = "tokyonight",
    })
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("rejects entry with missing colorscheme", function()
    local ok, err = schedule.validate_entry({
      start = "08:00", stop = "18:00",
    })
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("rejects entry with invalid background value", function()
    local ok, err = schedule.validate_entry({
      start = "08:00", stop = "18:00",
      colorscheme = "tokyonight", background = "purple",
    })
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)
end)

describe("schedule.preprocess", function()
  it("converts valid entries into parsed entries", function()
    local raw = {
      { start = "06:00", stop = "18:00", colorscheme = "day", background = "light" },
      { start = "18:00", stop = "06:00", colorscheme = "night" },
    }
    local parsed = schedule.preprocess(raw, "dark")
    assert.are.equal(2, #parsed)
    assert.are.equal(360,  parsed[1].start_time)
    assert.are.equal(1080, parsed[1].stop_time)
    assert.are.equal("light", parsed[1].background)
    assert.are.equal("dark",  parsed[2].background)  -- inherited from default
  end)

  it("skips and reports invalid entries", function()
    local errors = {}
    -- patch vim.notify to capture messages
    local orig = vim.notify
    vim.notify = function(msg, _) table.insert(errors, msg) end

    local parsed = schedule.preprocess({
      { start = "invalid", stop = "18:00", colorscheme = "x" },
      { start = "06:00",   stop = "18:00", colorscheme = "y" },
    }, "dark")

    vim.notify = orig
    assert.are.equal(1, #parsed)  -- bad entry skipped
    assert.are.equal(1, #errors)
  end)
end)

describe("schedule.get_active_entry", function()
  local parsed

  before_each(function()
    parsed = schedule.preprocess({
      { start = "06:00", stop = "18:00", colorscheme = "day",   background = "light" },
      { start = "18:00", stop = "06:00", colorscheme = "night", background = "dark"  },
    }, "dark")
  end)

  it("returns day entry at 12:00", function()
    local entry = schedule.get_active_entry(parsed, 720)  -- 12*60
    assert.are.equal("day", entry.colorscheme)
  end)

  it("returns night entry at 22:00", function()
    local entry = schedule.get_active_entry(parsed, 1320)  -- 22*60
    assert.are.equal("night", entry.colorscheme)
  end)

  it("returns night entry at 03:00 (overnight)", function()
    local entry = schedule.get_active_entry(parsed, 180)  -- 3*60
    assert.are.equal("night", entry.colorscheme)
  end)

  it("returns nil for empty schedule", function()
    assert.is_nil(schedule.get_active_entry({}, 720))
  end)
end)

describe("schedule.next_change_at", function()
  it("returns minutes until next boundary", function()
    local parsed = schedule.preprocess({
      { start = "06:00", stop = "18:00", colorscheme = "day", background = "light" },
    }, "dark")

    -- at 05:00 (300 mins), next boundary is 06:00 (+60 mins)
    assert.are.equal(60, schedule.next_change_at(parsed, 300))
    -- at 06:00 (360 mins), next boundary is 18:00 (+720 mins)
    assert.are.equal(720, schedule.next_change_at(parsed, 360))
  end)

  it("returns nil for empty schedule", function()
    assert.is_nil(schedule.next_change_at({}, 720))
  end)
end)
```

- [ ] **Step 2: Run tests — verify they fail (module doesn't exist)**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedFile tests/schedule_spec.lua"
```
Expected: errors about missing module `colorful-times.schedule`

- [ ] **Step 3: Create `schedule.lua`**

```lua
-- lua/colorful-times/schedule.lua
local M = {}

---@param str string
---@return integer|nil
function M.parse_time(str)
  local hour, min = str:match("^(%d%d?):(%d%d)$")
  if not hour then return nil end
  hour, min = tonumber(hour), tonumber(min)
  if hour >= 24 or min >= 60 then return nil end
  return hour * 60 + min
end

---@param entry table
---@return boolean, string?
function M.validate_entry(entry)
  if not entry.colorscheme or entry.colorscheme == "" then
    return false, "missing colorscheme"
  end
  if not M.parse_time(entry.start or "") then
    return false, "invalid start time: " .. tostring(entry.start)
  end
  if not M.parse_time(entry.stop or "") then
    return false, "invalid stop time: " .. tostring(entry.stop)
  end
  if entry.background and not vim.tbl_contains({ "light", "dark", "system" }, entry.background) then
    return false, "invalid background: " .. entry.background .. " (must be light, dark, or system)"
  end
  return true
end

---@param raw_schedule table
---@param default_background string
---@return ColorfulTimes.ParsedEntry[]
function M.preprocess(raw_schedule, default_background)
  local result = {}
  for idx, slot in ipairs(raw_schedule) do
    local ok, err = M.validate_entry(slot)
    if not ok then
      vim.notify(
        string.format("colorful-times: invalid schedule entry %d: %s", idx, err),
        vim.log.levels.ERROR
      )
    else
      table.insert(result, {
        start_time  = M.parse_time(slot.start),
        stop_time   = M.parse_time(slot.stop),
        colorscheme = slot.colorscheme,
        background  = slot.background or default_background,
      })
    end
  end
  return result
end

---@param parsed ColorfulTimes.ParsedEntry[]
---@param time_mins integer
---@return ColorfulTimes.ParsedEntry|nil
function M.get_active_entry(parsed, time_mins)
  for _, slot in ipairs(parsed) do
    local start_t = slot.start_time
    local stop_t  = slot.stop_time
    local current = time_mins

    if stop_t <= start_t then
      -- overnight: e.g. 22:00 -> 06:00
      if current < start_t then
        current = current + 1440
      end
      stop_t = stop_t + 1440
    end

    if current >= start_t and current < stop_t then
      return slot
    end
  end
  return nil
end

---@param parsed ColorfulTimes.ParsedEntry[]
---@param time_mins integer
---@return integer|nil
function M.next_change_at(parsed, time_mins)
  if #parsed == 0 then return nil end
  local min_diff = 1440  -- max 24h
  local found = false

  for _, slot in ipairs(parsed) do
    for _, boundary in ipairs({ slot.start_time, slot.stop_time }) do
      local diff = boundary - time_mins
      if diff <= 0 then diff = diff + 1440 end
      if diff < min_diff then
        min_diff = diff
        found = true
      end
    end
  end

  return found and min_diff or nil
end

return M
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedFile tests/schedule_spec.lua"
```
Expected: all tests pass

- [ ] **Step 5: Commit**

```bash
git add lua/colorful-times/schedule.lua tests/schedule_spec.lua
git commit -m "feat: add schedule.lua pure module with tests"
```

---

## Task 2: `system.lua` — OS dark/light detection

**Files:**
- Create: `lua/colorful-times/system.lua`
- Create: `tests/system_spec.lua`

- [ ] **Step 1: Create test file**

```lua
-- tests/system_spec.lua
describe("system.sysname", function()
  it("returns a non-empty string", function()
    local system = require("colorful-times.system")
    local name = system.sysname()
    assert.is_string(name)
    assert.is_true(#name > 0)
  end)

  it("caches the result (same value on second call)", function()
    local system = require("colorful-times.system")
    local a = system.sysname()
    local b = system.sysname()
    assert.are.equal(a, b)
  end)
end)

describe("system.get_background with function override", function()
  it("calls cb with the function's return value", function()
    local system = require("colorful-times.system")
    local M = require("colorful-times")
    M.config.system_background_detection = function() return "dark" end

    local result = nil
    system.get_background(function(bg) result = bg end, "light")

    -- system_background_detection function is called synchronously, so result is set immediately
    -- (the cb is called via vim.schedule, so we wait a tick)
    vim.wait(100, function() return result ~= nil end)
    assert.are.equal("dark", result)

    M.config.system_background_detection = nil
  end)
end)

describe("system.get_background fallback", function()
  it("calls cb with fallback on unsupported platform (mocked)", function()
    local system = require("colorful-times.system")
    -- Temporarily override sysname to simulate unsupported OS
    local orig_sysname = system.sysname
    system.sysname = function() return "Windows_NT" end

    local result = nil
    system.get_background(function(bg) result = bg end, "light")
    vim.wait(100, function() return result ~= nil end)
    assert.are.equal("light", result)

    system.sysname = orig_sysname
  end)
end)
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedFile tests/system_spec.lua"
```

- [ ] **Step 3: Create `system.lua`**

```lua
-- lua/colorful-times/system.lua
local M = {}
local uv = vim.uv

local _sysname = nil

---@return string
function M.sysname()
  if not _sysname then
    _sysname = uv.os_uname().sysname or "Unknown"
  end
  return _sysname
end

-- Spawn a process and call handle_result(exit_code) when done.
-- Drains stdout/stderr to prevent pipe blocking.
---@param cmd string
---@param args string[]
---@param handle_result fun(code: integer)
local function spawn_check(cmd, args, handle_result)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local handle
  handle = uv.spawn(cmd, { args = args, stdio = { nil, stdout, stderr } },
    function(code)
      stdout:read_stop(); stderr:read_stop()
      stdout:close();     stderr:close()
      handle:close()
      handle_result(code)
    end)
  stdout:read_start(function() end)
  stderr:read_start(function() end)
end

---@param cb fun(bg: string)
---@param fallback string
function M.get_background(cb, fallback)
  local config = require("colorful-times").config
  local sysname = M.sysname()

  -- User-supplied function (Linux)
  if type(config.system_background_detection) == "function" then
    local bg = config.system_background_detection()
    vim.schedule(function() cb(bg) end)
    return
  end

  -- User-supplied command table (Linux)
  if type(config.system_background_detection) == "table" then
    local cmd  = config.system_background_detection[1]
    local args = {}
    for i = 2, #config.system_background_detection do
      args[#args + 1] = config.system_background_detection[i]
    end
    spawn_check(cmd, args, function(code)
      vim.schedule(function() cb(code == 0 and "dark" or "light") end)
    end)
    return
  end

  if sysname == "Darwin" then
    spawn_check("defaults", { "read", "-g", "AppleInterfaceStyle" }, function(code)
      vim.schedule(function() cb(code == 0 and "dark" or "light") end)
    end)

  elseif sysname == "Linux" then
    -- Auto-detect KDE or GNOME
    local script = [[
      if [ "$XDG_CURRENT_DESKTOP" = "KDE" ] || [ "$XDG_SESSION_DESKTOP" = "KDE" ]; then
        if command -v kreadconfig6 &>/dev/null; then
          kreadconfig6 --group General --key ColorScheme --file kdeglobals | grep -q Dark && exit 0
          kreadconfig6 --group KDE --key LookAndFeelPackage | grep -qi dark && exit 0
        elif command -v kreadconfig5 &>/dev/null; then
          kreadconfig5 --group General --key ColorScheme --file kdeglobals | grep -q Dark && exit 0
        fi
        exit 1
      elif [ "$XDG_CURRENT_DESKTOP" = "GNOME" ] || [ "$XDG_SESSION_DESKTOP" = "GNOME" ]; then
        gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | grep -q prefer-dark && exit 0
        exit 1
      else
        exit 1
      fi
    ]]
    spawn_check("sh", { "-c", script }, function(code)
      vim.schedule(function() cb(code == 0 and "dark" or "light") end)
    end)

  else
    vim.schedule(function() cb(fallback) end)
  end
end

return M
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedFile tests/system_spec.lua"
```

- [ ] **Step 5: Commit**

```bash
git add lua/colorful-times/system.lua tests/system_spec.lua
git commit -m "feat: add system.lua OS appearance detection with tests"
```

---

## Task 3: `state.lua` — JSON persistence

**Files:**
- Create: `lua/colorful-times/state.lua`
- Create: `tests/state_spec.lua`

- [ ] **Step 1: Create test file**

```lua
-- tests/state_spec.lua
local state = require("colorful-times.state")

describe("state.path", function()
  it("returns a string ending in state.json", function()
    assert.is_truthy(state.path():match("state%.json$"))
  end)
end)

describe("state.load", function()
  it("returns {} for non-existent file", function()
    local orig_path = state.path
    state.path = function() return "/tmp/ct_test_nonexistent_" .. os.time() .. ".json" end
    assert.are.same({}, state.load())
    state.path = orig_path
  end)

  it("returns {} on parse error", function()
    local tmp = os.tmpname()
    local f = io.open(tmp, "w"); f:write("not json!!"); f:close()
    local orig_path = state.path
    state.path = function() return tmp end
    assert.are.same({}, state.load())
    state.path = orig_path
    os.remove(tmp)
  end)

  it("parses valid JSON", function()
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write(vim.json.encode({ enabled = false, schedule = {} }))
    f:close()
    local orig_path = state.path
    state.path = function() return tmp end
    local result = state.load()
    state.path = orig_path
    os.remove(tmp)
    assert.is_false(result.enabled)
  end)
end)

describe("state.save and state.load roundtrip", function()
  it("saves and reloads data correctly", function()
    local tmp = os.tmpname()
    os.remove(tmp)  -- ensure file doesn't exist yet
    local dir = tmp .. "_dir"
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/state.json"

    local orig_path = state.path
    state.path = function() return file end

    local data = {
      enabled = true,
      schedule = {
        { start = "06:00", stop = "18:00", colorscheme = "tokyonight-day", background = "light" },
      },
    }
    state.save(data)
    local loaded = state.load()
    state.path = orig_path

    vim.fn.delete(dir, "rf")

    assert.is_true(loaded.enabled)
    assert.are.equal(1, #loaded.schedule)
    assert.are.equal("tokyonight-day", loaded.schedule[1].colorscheme)
  end)
end)

describe("state.merge", function()
  local base = {
    enabled = true,
    schedule = { { start = "06:00", stop = "18:00", colorscheme = "base" } },
    default = { colorscheme = "default", background = "system" },
  }

  it("stored schedule wins over base", function()
    local result = state.merge(vim.deepcopy(base), {
      schedule = { { start = "09:00", stop = "17:00", colorscheme = "stored" } },
    })
    assert.are.equal("stored", result.schedule[1].colorscheme)
  end)

  it("stored enabled wins over base", function()
    local result = state.merge(vim.deepcopy(base), { enabled = false })
    assert.is_false(result.enabled)
  end)

  it("missing schedule key in stored leaves base intact", function()
    local result = state.merge(vim.deepcopy(base), { enabled = false })
    assert.are.equal("base", result.schedule[1].colorscheme)
  end)

  it("empty schedule array [] wins (clears base schedule)", function()
    local result = state.merge(vim.deepcopy(base), { schedule = {} })
    assert.are.same({}, result.schedule)
  end)

  it("missing enabled key in stored leaves base enabled", function()
    local result = state.merge(vim.deepcopy(base), {})
    assert.is_true(result.enabled)
  end)

  it("non-schedule keys from base are preserved", function()
    local result = state.merge(vim.deepcopy(base), { enabled = false })
    assert.are.equal("default", result.default.colorscheme)
  end)
end)
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedFile tests/state_spec.lua"
```

- [ ] **Step 3: Create `state.lua`**

```lua
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
  if not ok then
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
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedFile tests/state_spec.lua"
```

- [ ] **Step 5: Commit**

```bash
git add lua/colorful-times/state.lua tests/state_spec.lua
git commit -m "feat: add state.lua JSON persistence with tests"
```

---

## Task 4: Rewrite `init.lua`

Replace the existing stub with a clean v2 version. No logic, only config + metatable.

**Files:**
- Modify: `lua/colorful-times/init.lua`

- [ ] **Step 1: Rewrite `init.lua`**

```lua
-- lua/colorful-times/init.lua

---@class ColorfulTimes
local M = {}

---@class ColorfulTimes.ScheduleEntry
---@field start string          Start time "HH:MM"
---@field stop string           Stop time "HH:MM"
---@field colorscheme string    Colorscheme name
---@field background? string    "light" | "dark" | "system" | nil

---@class ColorfulTimes.ParsedEntry
---@field start_time integer    Minutes since midnight
---@field stop_time integer     Minutes since midnight
---@field colorscheme string
---@field background string

---@class ColorfulTimes.ThemeConfig
---@field light string|nil
---@field dark string|nil

---@class ColorfulTimes.DefaultConfig
---@field colorscheme string
---@field background string     "light" | "dark" | "system"
---@field themes ColorfulTimes.ThemeConfig

---@class ColorfulTimes.Config
---@field enabled boolean
---@field refresh_time integer  Milliseconds between appearance polls
---@field system_background_detection string[]|fun():string|nil
---@field default ColorfulTimes.DefaultConfig
---@field schedule ColorfulTimes.ScheduleEntry[]
---@field persist boolean       Whether TUI changes are written to state.json

M.config = {
  enabled = true,
  refresh_time = 5000,
  system_background_detection = nil,
  default = {
    colorscheme = "default",
    background = "system",
    themes = { light = nil, dark = nil },
  },
  schedule = {},
  persist = true,
}

-- Lazy-load core on first access of setup/toggle/reload/open
local _lazy_fns = { "setup", "toggle", "reload", "open" }
setmetatable(M, {
  __index = function(_, key)
    if vim.tbl_contains(_lazy_fns, key) then
      require("colorful-times.core")
      return M[key]
    end
  end,
})

return M
```

- [ ] **Step 2: Verify existing tests still pass (schedule/system/state)**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"
```

- [ ] **Step 3: Commit**

```bash
git add lua/colorful-times/init.lua
git commit -m "refactor: rewrite init.lua as clean v2 stub with type annotations"
```

---

## Task 5: `core.lua` — state machine and timers

The most complex module. Build the full state machine with timer orchestration.

**Files:**
- Create: `lua/colorful-times/core.lua`
- Create: `tests/core_spec.lua`

- [ ] **Step 1: Create test file**

```lua
-- tests/core_spec.lua
-- Core tests use mocked schedule + system modules to avoid real timers/spawns.

describe("core module loading", function()
  it("loads without error", function()
    assert.has_no.errors(function()
      require("colorful-times.core")
    end)
  end)
end)

describe("core.setup", function()
  it("sets enabled state from config", function()
    local M = require("colorful-times")
    local core = require("colorful-times.core")

    M.config.enabled = true
    M.config.schedule = {}
    M.config.default.background = "dark"
    M.config.default.colorscheme = "default"

    -- Should not throw even with no schedule
    assert.has_no.errors(function()
      core.setup(M.config)
    end)
  end)
end)

describe("core.toggle", function()
  it("flips M.config.enabled", function()
    local M    = require("colorful-times")
    local core = require("colorful-times.core")

    M.config.enabled = true
    core.setup(M.config)

    local before = M.config.enabled
    core.toggle()
    assert.are.equal(not before, M.config.enabled)

    core.toggle()  -- restore
    assert.are.equal(before, M.config.enabled)
  end)
end)
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedFile tests/core_spec.lua"
```

- [ ] **Step 3: Create `core.lua`**

```lua
-- lua/colorful-times/core.lua
local M        = require("colorful-times")
local schedule = require("colorful-times.schedule")
local system   = require("colorful-times.system")
local state    = require("colorful-times.state")
local uv       = vim.uv

-- Module-level mutable state
local timer      -- uv_timer_t|nil  (schedule boundary timer)
local poll_timer -- uv_timer_t|nil  (appearance poll timer)
local previous_bg  -- string|nil
local focused = true

local function stop_timer(t)
  if t and not t:is_closing() then
    t:stop()
    t:close()
  end
end

-- Return current time as minutes since midnight
local function now_mins()
  local d = os.date("*t")
  return d.hour * 60 + d.min
end

-- Determine the colorscheme + background to apply right now.
-- Returns: colorscheme string, background string
local function resolve_theme()
  local cfg    = M.config
  local parsed = schedule.preprocess(cfg.schedule, cfg.default.background)
  local active = M.config.enabled and schedule.get_active_entry(parsed, now_mins())

  local bg, cs
  if active then
    bg = active.background
    cs = active.colorscheme
  else
    bg = cfg.default.background
    -- theme-specific default colorscheme
    if bg ~= "system" and cfg.default.themes and cfg.default.themes[bg] then
      cs = cfg.default.themes[bg]
    else
      cs = cfg.default.colorscheme
    end
  end
  return cs, bg
end

-- Set colorscheme + background synchronously (must be called from main thread / vim.schedule)
local function set_colorscheme(cs, bg)
  previous_bg    = bg
  vim.o.background = bg
  local ok, err = pcall(vim.cmd.colorscheme, cs)
  if not ok then
    vim.notify("colorful-times: failed to apply colorscheme '" .. cs .. "': " .. err,
      vim.log.levels.ERROR)
  end
end

-- Two-phase apply: sync fallback first, then async system check if needed.
function M.apply_colorscheme()
  local cs, bg = resolve_theme()

  if bg ~= "system" then
    -- Non-system: apply directly
    vim.schedule(function() set_colorscheme(cs, bg) end)
    return
  end

  -- System background: apply fallback immediately, then correct asynchronously
  local fallback = previous_bg or vim.o.background or "dark"
  local fallback_cs = cs
  if M.config.default.themes and M.config.default.themes[fallback] then
    fallback_cs = M.config.default.themes[fallback]
  end

  -- Phase 1: sync fallback
  vim.schedule(function() set_colorscheme(fallback_cs, fallback) end)

  -- Phase 2: async real value
  system.get_background(function(detected_bg)
    if detected_bg ~= previous_bg then
      local real_cs = cs
      if M.config.default.themes and M.config.default.themes[detected_bg] then
        real_cs = M.config.default.themes[detected_bg]
      end
      vim.schedule(function() set_colorscheme(real_cs, detected_bg) end)
    end
  end, fallback)
end

-- Schedule the one-shot timer to fire at the next schedule boundary
local function arm_schedule_timer()
  stop_timer(timer)
  timer = nil
  if not M.config.enabled then return end

  local parsed   = schedule.preprocess(M.config.schedule, M.config.default.background)
  local diff_min = schedule.next_change_at(parsed, now_mins())
  if not diff_min then return end

  timer = uv.new_timer()
  timer:start(diff_min * 60 * 1000, 0, function()
    vim.schedule(function()
      M.apply_colorscheme()
      arm_schedule_timer()
    end)
  end)
end

-- Check on each poll tick whether we actually need to query the OS
local function needs_system_poll()
  local parsed = schedule.preprocess(M.config.schedule, M.config.default.background)
  local active = M.config.enabled and schedule.get_active_entry(parsed, now_mins())
  local bg     = active and active.background or M.config.default.background
  return bg == "system"
end

-- Start the repeating appearance poll timer
local function start_poll_timer()
  stop_timer(poll_timer)
  poll_timer = nil

  local sysname = system.sysname()
  if sysname ~= "Darwin" and sysname ~= "Linux"
    and type(M.config.system_background_detection) ~= "function"
    and type(M.config.system_background_detection) ~= "table"
  then
    return  -- no system detection available
  end

  local fallback = previous_bg or vim.o.background or "dark"
  poll_timer = uv.new_timer()
  poll_timer:start(0, M.config.refresh_time, function()
    if not focused then return end
    if not needs_system_poll() then return end
    system.get_background(function(detected_bg)
      if detected_bg ~= previous_bg then
        M.apply_colorscheme()
      end
    end, fallback)
  end)
end

local autocmd_registered = false

local function register_focus_autocmds()
  if autocmd_registered then return end
  autocmd_registered = true
  local grp = vim.api.nvim_create_augroup("ColorfulTimesFocus", { clear = true })
  vim.api.nvim_create_autocmd("FocusLost", {
    group = grp,
    callback = function() focused = false end,
  })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = grp,
    callback = function()
      focused = true
      -- Re-check appearance immediately on focus regain
      if needs_system_poll() then
        local fallback = previous_bg or vim.o.background or "dark"
        system.get_background(function(detected_bg)
          if detected_bg ~= previous_bg then
            M.apply_colorscheme()
          end
        end, fallback)
      end
    end,
  })
end

local function enable_plugin()
  M.apply_colorscheme()
  arm_schedule_timer()
  start_poll_timer()
  vim.notify("colorful-times: enabled", vim.log.levels.INFO)
end

local function disable_plugin()
  stop_timer(timer);      timer = nil
  stop_timer(poll_timer); poll_timer = nil
  -- Apply with enabled=false so resolve_theme() returns default
  M.apply_colorscheme()
  vim.notify("colorful-times: disabled", vim.log.levels.INFO)
end

function M.toggle()
  M.config.enabled = not M.config.enabled
  if M.config.enabled then enable_plugin() else disable_plugin() end
end

function M.reload()
  stop_timer(timer);      timer = nil
  stop_timer(poll_timer); poll_timer = nil
  previous_bg = nil
  schedule.preprocess(M.config.schedule, M.config.default.background)  -- re-validate
  M.apply_colorscheme()
  arm_schedule_timer()
  start_poll_timer()
end

function M.setup(opts)
  -- Merge user opts into config
  if opts then
    if opts.default then
      M.config.default = vim.tbl_deep_extend("force", M.config.default, opts.default)
      opts.default = nil
    end
    for k, v in pairs(opts) do
      M.config[k] = v
    end
  end

  -- Merge persisted state on top
  local stored = state.load()
  if next(stored) then
    M.config = state.merge(M.config, stored)
  end

  register_focus_autocmds()

  if M.config.enabled then
    M.apply_colorscheme()
    arm_schedule_timer()
    start_poll_timer()
  end
end

-- TUI entry point
function M.open()
  require("colorful-times.tui").open()
end

return M
```

- [ ] **Step 4: Run all tests**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"
```
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lua/colorful-times/core.lua tests/core_spec.lua
git commit -m "feat: add core.lua state machine with FocusLost pause and two-phase apply"
```

---

## Task 6: `plugin/colorful-times.lua` — command registration

**Files:**
- Create: `plugin/colorful-times.lua`

- [ ] **Step 1: Create `plugin/colorful-times.lua`**

```lua
-- plugin/colorful-times.lua
-- Loaded automatically by Neovim at startup via the plugin/ directory.
-- Must be fast: only registers commands, no heavy requires.

vim.api.nvim_create_user_command("ColorfulTimes", function()
  require("colorful-times.core")
  require("colorful-times").open()
end, { desc = "Open colorful-times schedule manager" })

vim.api.nvim_create_user_command("ColorfulTimesToggle", function()
  require("colorful-times.core")
  require("colorful-times").toggle()
end, { desc = "Toggle colorful-times on/off" })

vim.api.nvim_create_user_command("ColorfulTimesReload", function()
  require("colorful-times.core")
  require("colorful-times").reload()
end, { desc = "Reload colorful-times configuration" })
```

- [ ] **Step 2: Verify existing tests still pass**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"
```

- [ ] **Step 3: Commit**

```bash
git add plugin/colorful-times.lua
git commit -m "feat: add plugin/colorful-times.lua command registration"
```

---

## Task 7: `health.lua` — checkhealth integration

**Files:**
- Create: `lua/colorful-times/health.lua`

- [ ] **Step 1: Create `health.lua`**

```lua
-- lua/colorful-times/health.lua
local M = {}

function M.check()
  local health = vim.health

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

  -- snacks.nvim (optional)
  local has_snacks = pcall(require, "snacks")
  if has_snacks then
    health.ok("snacks.nvim found (TUI fully functional)")
  else
    health.info("snacks.nvim not found — TUI will use vim.ui.input / vim.ui.select fallback")
  end

  -- State file
  local state = require("colorful-times.state")
  local path  = state.path()
  local dir   = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 1 or vim.fn.mkdir(dir, "p") == 1 then
    health.ok("State directory writable: " .. dir)
  else
    health.warn("State directory not writable: " .. dir .. " (TUI changes won't persist)")
  end

  -- Schedule validation
  local M_cfg = require("colorful-times")
  local schedule = require("colorful-times.schedule")
  local bad = 0
  for idx, entry in ipairs(M_cfg.config.schedule) do
    local ok, err = schedule.validate_entry(entry)
    if not ok then
      health.warn(string.format("Schedule entry %d is invalid: %s", idx, err))
      bad = bad + 1
    end
  end
  if bad == 0 then
    health.ok(string.format("Schedule: %d entries, all valid", #M_cfg.config.schedule))
  end

  -- Current colorscheme
  local cs = vim.g.colors_name or "(none)"
  health.info("Current colorscheme: " .. cs)
end

return M
```

- [ ] **Step 2: Manually verify in Neovim**

Run `:checkhealth colorful-times` — confirm all sections render.

- [ ] **Step 3: Commit**

```bash
git add lua/colorful-times/health.lua
git commit -m "feat: add health.lua checkhealth integration"
```

---

## Task 8: `tui.lua` — Table Manager TUI

The most involved task. Build the floating window, keymaps, add/edit/delete forms, and snacks integration with graceful fallback.

**Files:**
- Create: `lua/colorful-times/tui.lua`

- [ ] **Step 1: Create `tui.lua`**

```lua
-- lua/colorful-times/tui.lua
-- Table Manager TUI. Loaded only on demand (:ColorfulTimes / M.open()).
-- Uses snacks.nvim when available; falls back to vim.ui.* otherwise.

local M      = {}
local api    = vim.api
local ct     = require("colorful-times")
local sched  = require("colorful-times.schedule")

local VERSION = "2.0.0"

-- ─── Snacks detection ────────────────────────────────────────────────────────

local function has_snacks()
  return pcall(require, "snacks")
end

-- ─── Window state ────────────────────────────────────────────────────────────

local state = {
  buf     = nil,  -- buffer handle
  win     = nil,  -- window handle
  cursor  = 1,    -- 1-indexed selected row (into schedule)
}

local NS = api.nvim_create_namespace("colorful_times_tui")

-- ─── Rendering ───────────────────────────────────────────────────────────────

local COL_WIDTHS = { 7, 7, 30, 8 }  -- START STOP COLORSCHEME BG
local HEADER_SEP = string.rep("─", COL_WIDTHS[1] + COL_WIDTHS[2] + COL_WIDTHS[3] + COL_WIDTHS[4] + 9)

local function pad(str, width)
  str = tostring(str or "")
  if #str >= width then return str:sub(1, width - 1) .. " " end
  return str .. string.rep(" ", width - #str)
end

local function render()
  if not (state.buf and api.nvim_buf_is_valid(state.buf)) then return end

  api.nvim_buf_set_option(state.buf, "modifiable", true)
  api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)

  local lines = {}
  -- Status bar
  local status = ct.config.enabled
    and "  [●] ENABLED  " .. VERSION
    or  "  [○] DISABLED " .. VERSION
  table.insert(lines, status)
  table.insert(lines, HEADER_SEP)

  -- Header row
  table.insert(lines, string.format(
    "  %s%s%s%s",
    pad("START", COL_WIDTHS[1]),
    pad("STOP",  COL_WIDTHS[2]),
    pad("COLORSCHEME", COL_WIDTHS[3]),
    pad("BG", COL_WIDTHS[4])
  ))
  table.insert(lines, HEADER_SEP)

  -- Schedule rows
  local schedule = ct.config.schedule
  if #schedule == 0 then
    table.insert(lines, "  (no entries — press [a] to add)")
  else
    for _, entry in ipairs(schedule) do
      table.insert(lines, string.format(
        "  %s%s%s%s",
        pad(entry.start,        COL_WIDTHS[1]),
        pad(entry.stop,         COL_WIDTHS[2]),
        pad(entry.colorscheme,  COL_WIDTHS[3]),
        pad(entry.background or "—", COL_WIDTHS[4])
      ))
    end
  end

  table.insert(lines, HEADER_SEP)
  table.insert(lines, "  [a]dd [e]dit [d]el [t]oggle [r]eload [?]help [q]uit")

  api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  api.nvim_buf_set_option(state.buf, "modifiable", false)

  -- Highlight selected row (rows start at line 5 = index 4, 0-based)
  local HEADER_LINES = 4
  local selected_line = HEADER_LINES + state.cursor - 1
  if #schedule > 0 then
    api.nvim_buf_add_highlight(state.buf, NS, "Visual", selected_line, 0, -1)
  end
end

-- ─── Form helpers ─────────────────────────────────────────────────────────────

-- Prompt for a validated HH:MM time string.
-- Calls cb(time_str) on success, cb(nil) on cancel.
local function prompt_time(prompt_text, default, cb)
  local function ask()
    if has_snacks() then
      require("snacks").input({
        prompt  = prompt_text,
        default = default or "",
      }, function(value)
        if not value then cb(nil); return end
        if sched.parse_time(value) then
          cb(value)
        else
          vim.notify("Invalid time: '" .. value .. "' (use HH:MM)", vim.log.levels.WARN)
          ask()  -- re-prompt
        end
      end)
    else
      vim.ui.input({ prompt = prompt_text .. ": ", default = default or "" }, function(value)
        if not value then cb(nil); return end
        if sched.parse_time(value) then
          cb(value)
        else
          vim.notify("Invalid time: '" .. value .. "' (use HH:MM)", vim.log.levels.WARN)
          ask()
        end
      end)
    end
  end
  ask()
end

-- Fuzzy colorscheme picker with live preview.
-- Calls cb(name) on confirm, cb(nil) on cancel.
local function pick_colorscheme(default, cb)
  local original_cs = vim.g.colors_name
  local original_bg = vim.o.background

  local schemes = vim.fn.getcompletion("", "color")

  local function revert()
    pcall(vim.cmd.colorscheme, original_cs)
    vim.o.background = original_bg
  end

  if has_snacks() then
    require("snacks").picker.pick({
      title  = "Colorscheme",
      items  = vim.tbl_map(function(s) return { text = s } end, schemes),
      format = "text",
      on_change = function(_, item)
        if item then
          pcall(vim.cmd.colorscheme, item.text)
        end
      end,
      confirm = function(picker, item)
        picker:close()
        if item then
          cb(item.text)
        else
          revert()
          cb(nil)
        end
      end,
      on_close = function()
        -- only revert if confirm wasn't called (picker closed without selection)
      end,
    })
  else
    -- Fallback: vim.ui.select (no live preview)
    -- Cap at 200 to avoid unusable overflow
    local display = #schemes > 200 and vim.list_slice(schemes, 1, 200) or schemes
    vim.ui.select(display, {
      prompt = "Colorscheme (showing first 200): ",
    }, function(choice)
      if choice then cb(choice) else cb(nil) end
    end)
  end
end

-- Sequential form: collect all fields for an entry, call cb(entry) or cb(nil) on cancel.
local function entry_form(existing, cb)
  prompt_time("Start time (HH:MM)", existing and existing.start, function(start)
    if not start then cb(nil); return end
    prompt_time("Stop time (HH:MM)", existing and existing.stop, function(stop)
      if not stop then cb(nil); return end
      pick_colorscheme(existing and existing.colorscheme, function(cs)
        if not cs then cb(nil); return end
        vim.ui.select(
          { "system", "dark", "light" },
          { prompt = "Background: " },
          function(bg)
            if not bg then cb(nil); return end
            cb({ start = start, stop = stop, colorscheme = cs, background = bg })
          end
        )
      end)
    end)
  end)
end

-- ─── Actions ─────────────────────────────────────────────────────────────────

local function save_and_reload()
  local core = require("colorful-times.core")
  if ct.config.persist then
    require("colorful-times.state").save({
      enabled  = ct.config.enabled,
      schedule = ct.config.schedule,
    })
  end
  core.reload()
  render()
end

local function action_add()
  entry_form(nil, function(entry)
    if not entry then return end
    table.insert(ct.config.schedule, entry)
    state.cursor = #ct.config.schedule
    save_and_reload()
  end)
end

local function action_edit()
  local idx = state.cursor
  if idx < 1 or idx > #ct.config.schedule then return end
  local existing = ct.config.schedule[idx]
  entry_form(existing, function(entry)
    if not entry then return end
    ct.config.schedule[idx] = entry
    save_and_reload()
  end)
end

local function action_delete()
  local idx = state.cursor
  if idx < 1 or idx > #ct.config.schedule then return end
  local entry = ct.config.schedule[idx]
  vim.ui.select({ "Yes", "No" }, {
    prompt = string.format("Delete %s–%s %s? ", entry.start, entry.stop, entry.colorscheme),
  }, function(choice)
    if choice ~= "Yes" then return end
    table.remove(ct.config.schedule, idx)
    if state.cursor > #ct.config.schedule and state.cursor > 1 then
      state.cursor = state.cursor - 1
    end
    save_and_reload()
  end)
end

local function action_toggle()
  require("colorful-times.core").toggle()
  render()
end

local function action_reload()
  require("colorful-times.core").reload()
  render()
  vim.notify("colorful-times: config reloaded", vim.log.levels.INFO)
end

local function action_help()
  local help = {
    "colorful-times keymaps:",
    "  j / ↓      move down",
    "  k / ↑      move up",
    "  a          add entry",
    "  e / Enter  edit entry",
    "  d / x      delete entry",
    "  t          toggle enabled",
    "  r          reload config",
    "  q / Esc    close",
  }
  vim.notify(table.concat(help, "\n"), vim.log.levels.INFO)
end

local function cursor_move(delta)
  local n = math.max(1, #ct.config.schedule)
  state.cursor = math.max(1, math.min(n, state.cursor + delta))
  render()
end

-- ─── Open / Close ─────────────────────────────────────────────────────────────

local function close()
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
end

function M.open()
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_set_current_win(state.win)
    return
  end

  -- Create buffer
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(buf, "buftype",    "nofile")
  api.nvim_buf_set_option(buf, "bufhidden",  "wipe")
  api.nvim_buf_set_option(buf, "filetype",   "colorful-times")
  api.nvim_buf_set_option(buf, "modifiable", false)

  -- Compute window size
  local ui       = api.nvim_list_uis()[1]
  local width    = math.floor(ui.width * 0.6)
  local n_rows   = math.max(10, #ct.config.schedule + 6)  -- header + footer rows
  local height   = math.min(n_rows, math.floor(ui.height * 0.8))
  local row      = math.floor((ui.height - height) / 2)
  local col      = math.floor((ui.width  - width)  / 2)

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
    title    = " Colorful Times ",
    title_pos = "center",
  })

  state.buf    = buf
  state.win    = win
  state.cursor = math.max(1, math.min(state.cursor, math.max(1, #ct.config.schedule)))

  -- Keymaps (buffer-local, normal mode)
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
  end

  map("j",      function() cursor_move(1)  end)
  map("<Down>", function() cursor_move(1)  end)
  map("k",      function() cursor_move(-1) end)
  map("<Up>",   function() cursor_move(-1) end)
  map("a",      action_add)
  map("e",      action_edit)
  map("<CR>",   action_edit)
  map("d",      action_delete)
  map("x",      action_delete)
  map("t",      action_toggle)
  map("r",      action_reload)
  map("?",      action_help)
  map("q",      close)
  map("<Esc>",  close)

  render()
end

return M
```

- [ ] **Step 2: Manual smoke test in Neovim**

```
:lua require("colorful-times").setup({})
:ColorfulTimes
```
- Verify the window opens, keymaps work, `a` opens the add form
- Press `?` to see help
- Press `q` to close

- [ ] **Step 3: Commit**

```bash
git add lua/colorful-times/tui.lua
git commit -m "feat: add tui.lua Table Manager with snacks integration and vim.ui fallback"
```

---

## Task 9: Delete legacy files and update CI

**Files:**
- Delete: `lua/colorful-times/impl.lua`
- Delete: `tests/colorful_times_spec.lua`
- Modify: `tests/minimal_init.vim`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Delete legacy files**

```bash
git rm lua/colorful-times/impl.lua
git rm tests/colorful_times_spec.lua
```

- [ ] **Step 2: Update `tests/minimal_init.vim`**

Keep existing content, just update any version references and confirm the test runner still works:

```vim
" tests/minimal_init.vim
set rtp+=.
set rtp+=~/.local/share/nvim/site/pack/plugins/start/plenary.nvim

runtime plugin/plenary.vim
```

- [ ] **Step 3: Update CI — drop Lua version matrix**

In `.github/workflows/ci.yml`, remove the `lua-version` matrix and the `Set up Lua` step (Neovim 0.12 ships its own LuaJIT):

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        neovim-version: ["stable", "nightly"]

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Neovim
        uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: ${{ matrix['neovim-version'] }}

      - name: Install Dependencies
        run: |
          nvim --headless +'!mkdir -p ~/.local/share/nvim/site/pack/plugins/start' +qall
          git clone --depth 1 https://github.com/nvim-lua/plenary.nvim \
            ~/.local/share/nvim/site/pack/plugins/start/plenary.nvim

      - name: Run Tests
        run: |
          nvim --headless \
            -u tests/minimal_init.vim \
            -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"
```

- [ ] **Step 4: Run full test suite**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"
```
Expected: all tests pass, no reference to impl.lua

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: delete impl.lua and legacy spec, update CI to drop Lua version matrix"
```

---

## Task 10: Update docs — README and vimdoc

**Files:**
- Modify: `.github/README.md`
- Modify: `doc/colorful-times.txt`

- [ ] **Step 1: Update README**

Replace the Requirements section to say `Neovim >= 0.12.0`. Add the TUI section:

```markdown
## Requirements

- Neovim >= 0.12.0
- [snacks.nvim](https://github.com/folke/snacks.nvim) (optional — enables fuzzy colorscheme picker with live preview in the TUI; falls back to `vim.ui.*` without it)

## Schedule Manager TUI

Run `:ColorfulTimes` to open the interactive schedule manager:

```
  ┌─────────────────── Colorful Times ─────────────────────┐
  │  [●] ENABLED  2.0.0                                     │
  │ ────────────────────────────────────────────────────── │
  │  START   STOP    COLORSCHEME                   BG       │
  │ ────────────────────────────────────────────────────── │
  │  06:00   18:00   tokyonight-day                light    │
  │  18:00   06:00   tokyonight                    dark     │
  │ ────────────────────────────────────────────────────── │
  │  [a]dd [e]dit [d]el [t]oggle [r]eload [?]help [q]uit  │
  └─────────────────────────────────────────────────────────┘
```

Edits are persisted to `~/.local/share/nvim/colorful-times/state.json` and survive restarts.
Set `persist = false` in your config to disable persistence.

## Commands

| Command | Description |
|---------|-------------|
| `:ColorfulTimes` | Open the schedule manager TUI |
| `:ColorfulTimesToggle` | Toggle the plugin on/off |
| `:ColorfulTimesReload` | Reload config from disk |

## Health Check

Run `:checkhealth colorful-times` to verify your setup.
```

- [ ] **Step 2: Update `doc/colorful-times.txt`**

Add TUI section, update version to 0.12+, document new commands and `persist` config key, and document `M.open()` API.

- [ ] **Step 3: Run tests to confirm nothing broke**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"
```

- [ ] **Step 4: Commit**

```bash
git add .github/README.md doc/colorful-times.txt
git commit -m "docs: update README and vimdoc for v2 (TUI, commands, new requirements)"
```

---

## Task 11: Final integration and .gitignore update

- [ ] **Step 1: Add `.superpowers/` to `.gitignore`**

```bash
echo ".superpowers/" >> .gitignore
git add .gitignore
git commit -m "chore: ignore .superpowers/ brainstorm artifacts"
```

- [ ] **Step 2: Full test suite run**

```bash
nvim --headless -u tests/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"
```
All tests must pass.

- [ ] **Step 3: Manual end-to-end smoke test**

In a real Neovim session:
1. `require("colorful-times").setup({ default = { background = "dark" } })` — applies colorscheme
2. `:ColorfulTimes` — opens TUI
3. Press `a` — add a schedule entry, complete all four prompts
4. Press `e` — edit the new entry
5. Press `d` — delete it (confirm "Yes")
6. Press `t` — toggle disabled, verify notify message
7. Press `t` — toggle back enabled
8. Press `q` — close TUI
9. `:checkhealth colorful-times` — all checks green
10. Restart Neovim, verify added entries persisted

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: final v2 integration cleanup"
```
