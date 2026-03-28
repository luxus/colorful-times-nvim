# Standardize Error Notification Patterns

Ensure all error notifications use "colorful-times:" prefix consistently.

**Implementation details:**
- Audit all `vim.notify` calls across all modules:
  - `state.lua`: "colorful-times: failed to parse state file", "colorful-times: could not write state file"
  - `schedule.lua`: "colorful-times: invalid schedule entry %d: %s"
  - `core.lua`: "colorful-times: failed to apply colorscheme '%s': %s", "colorful-times: enabled", "colorful-times: disabled"
  - `tui.lua`: "Invalid time: '%s' (use HH:MM)", "colorful-times: config reloaded"
- Fix missing prefixes:
  - tui.lua: "Invalid time" → "colorful-times: invalid time"
  - Any other generic messages
- Create helper `notify(msg, level)` in each module if needed for consistency

**Files to modify:**
- `lua/colorful-times/tui.lua` - Add prefix to user-facing errors
- Any other files with inconsistent prefixes

**Acceptance criteria:**
- All error/warning/info messages prefixed with "colorful-times:"
- Consistent capitalization and formatting
- All existing tests pass
