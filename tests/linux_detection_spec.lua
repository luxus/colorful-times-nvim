describe("system Linux auto-detection regressions", function()
  local system
  local plugin
  local orig_sysname
  local orig_executable
  local orig_spawn
  local orig_new_pipe
  local orig_env

  local function stub_spawn(expected_cmd, output)
    vim.uv.new_pipe = function()
      local pipe = {}
      function pipe:read_start(cb)
        self._read_cb = cb
      end
      function pipe:read_stop() end
      function pipe:close() end
      return pipe
    end

    vim.uv.spawn = function(cmd, opts, on_exit)
      assert.are.equal(expected_cmd, cmd)
      local stdout = opts.stdio[2]
      vim.schedule(function()
        if stdout and stdout._read_cb and output then
          stdout._read_cb(nil, output)
        end
        on_exit(0)
      end)
      return {
        is_closing = function() return false end,
        close = function() end,
      }
    end
  end

  before_each(function()
    package.loaded["colorful-times.system"] = nil
    package.loaded["colorful-times"] = nil
    system = require("colorful-times.system")
    plugin = require("colorful-times")
    orig_sysname = system.sysname
    orig_executable = vim.fn.executable
    orig_spawn = vim.uv.spawn
    orig_new_pipe = vim.uv.new_pipe
    orig_env = {
      current = vim.env.XDG_CURRENT_DESKTOP,
      session = vim.env.XDG_SESSION_DESKTOP,
    }
  end)

  after_each(function()
    system.sysname = orig_sysname
    vim.fn.executable = orig_executable
    vim.uv.spawn = orig_spawn
    vim.uv.new_pipe = orig_new_pipe
    vim.env.XDG_CURRENT_DESKTOP = orig_env.current
    vim.env.XDG_SESSION_DESKTOP = orig_env.session
    plugin.config.system_background_detection = nil
    plugin.config.system_background_detection_script = nil
    package.loaded["colorful-times.system"] = nil
    package.loaded["colorful-times"] = nil
  end)

  it("detects GNOME from composite desktop names without shelling through sh", function()
    system.sysname = function() return "Linux" end
    vim.env.XDG_CURRENT_DESKTOP = "ubuntu:GNOME"
    vim.env.XDG_SESSION_DESKTOP = "ubuntu"
    vim.fn.executable = function(cmd)
      return cmd == "gsettings" and 1 or 0
    end
    stub_spawn("gsettings", "'prefer-dark'\n")

    local result
    system.get_background(function(bg) result = bg end, "light")

    vim.wait(100, function() return result ~= nil end)
    assert.are.equal("dark", result)
  end)

  it("detects KDE from composite desktop names and prefers kreadconfig6", function()
    system.sysname = function() return "Linux" end
    vim.env.XDG_CURRENT_DESKTOP = "plasma:KDE"
    vim.env.XDG_SESSION_DESKTOP = "plasma"
    vim.fn.executable = function(cmd)
      if cmd == "kreadconfig6" then
        return 1
      end
      return 0
    end
    stub_spawn("kreadconfig6", "BreezeDark\n")

    local result
    system.get_background(function(bg) result = bg end, "light")

    vim.wait(100, function() return result ~= nil end)
    assert.are.equal("dark", result)
  end)
end)
