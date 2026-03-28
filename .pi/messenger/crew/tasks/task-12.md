# Add Missing EmmyLua Annotations to Undocumented Functions

Add complete EmmyLua annotations to all functions lacking documentation.

**Implementation details:**
- Audit all functions in all modules for missing annotations:
  - `state.lua`: `path()`, `load()`, `save()`, `merge()` - some missing return type details
  - `core.lua`: Many internal functions lack annotations (`stop_timer`, `now_mins`, `resolve_theme`, `set_colorscheme`, `arm_schedule_timer`, `needs_system_poll`, `start_poll_timer`, `register_focus_autocmds`, `enable_plugin`, `disable_plugin`)
  - `schedule.lua`: All functions have annotations ✓
  - `system.lua`: `sysname()` has annotation, `spawn_check` and `get_background` lack param details
  - `tui.lua`: Many internal functions lack annotations (`has_snacks`, `pad`, `render`, `prompt_time`, `pick_colorscheme`, `entry_form`, all action_* functions, `cursor_move`, `close`, `open`)
  - `init.lua`: Config class annotations are good ✓
- Add `---@param`, `---@return`, `---@class` as needed
- Follow existing code style from AGENTS.md

**Files to modify:**
- `lua/colorful-times/state.lua` - Complete any partial annotations
- `lua/colorful-times/core.lua` - Add annotations to all internal functions
- `lua/colorful-times/system.lua` - Complete param annotations
- `lua/colorful-times/tui.lua` - Add annotations to all internal functions

**Acceptance criteria:**
- All public functions have complete EmmyLua annotations
- All internal functions have annotations where type information adds value
- No regressions in functionality
- All existing tests pass
