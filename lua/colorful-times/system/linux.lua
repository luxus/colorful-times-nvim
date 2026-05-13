-- lua/colorful-times/system/linux.lua

local M = {}

local function is_kde(env)
  return env.current_desktop():find("KDE", 1, true) ~= nil
end

local function is_gnome(env)
  return env.current_desktop():find("GNOME", 1, true) ~= nil
end

function M.plan(cfg, env)
  if cfg.system_background_detection_script ~= nil then
    if env.is_executable_file(cfg.system_background_detection_script) then
      return {
        available = true,
        backend = "script",
        detail = "custom detection script",
        kind = "command_exit_code",
        cmd = cfg.system_background_detection_script,
        args = {},
      }
    end

    return {
      available = false,
      backend = "script",
      detail = "custom detection script is missing or not executable",
      kind = "unavailable",
      error = "invalid detection script: " .. tostring(cfg.system_background_detection_script),
    }
  end

  if is_kde(env) then
    local reader
    if env.executable("kreadconfig6") then
      reader = "kreadconfig6"
    elseif env.executable("kreadconfig5") then
      reader = "kreadconfig5"
    end

    if reader then
      return {
        available = true,
        backend = "linux-kde",
        detail = "KDE desktop detection",
        kind = "command_output_contains",
        cmd = reader,
        args = { "--group", "General", "--key", "ColorScheme", "--file", "kdeglobals" },
        dark_pattern = "Dark",
      }
    end

    return {
      available = false,
      backend = "linux-kde",
      detail = "KDE detected but kreadconfig5/6 is unavailable",
      kind = "unavailable",
    }
  end

  if is_gnome(env) then
    if env.executable("gsettings") then
      return {
        available = true,
        backend = "linux-gnome",
        detail = "GNOME desktop detection",
        kind = "command_output_contains",
        cmd = "gsettings",
        args = { "get", "org.gnome.desktop.interface", "color-scheme" },
        dark_pattern = "prefer-dark",
      }
    end

    return {
      available = false,
      backend = "linux-gnome",
      detail = "GNOME detected but gsettings is unavailable",
      kind = "unavailable",
    }
  end

  return {
    available = false,
    backend = "linux",
    detail = "no supported Linux desktop detected (expected KDE or GNOME)",
    kind = "unavailable",
  }
end

return M
