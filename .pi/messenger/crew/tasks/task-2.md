# Cache Parsed Schedule in core.lua

Add module-level cache for `schedule.preprocess()` results to eliminate redundant parsing.

**Implementation details:**
- Add `_schedule_cache = { hash = nil, parsed = nil, default_bg = nil }` at module level
- Create `get_cached_schedule(config_schedule, default_bg)` helper:
  - Compute simple hash of schedule array (e.g., vim.inspect or serialization)
  - Return cached result if hash matches, otherwise preprocess and cache
- Replace all 4 calls to `schedule.preprocess()` in core.lua with cached version:
  - `resolve_theme()` 
  - `arm_schedule_timer()`
  - `needs_system_poll()`
  - `reload()` (already calls preprocess, ensure it clears cache)

**Files to modify:**
- `lua/colorful-times/core.lua` - Add cache module variable and helper function

**Acceptance criteria:**
- schedule.preprocess() called only once per unique schedule
- Cache invalidates when schedule changes
- Cache clears on reload()
- No memory leaks (cache replaced, not accumulated)
- All existing tests pass
- Add test: Verify preprocess called once for multiple core operations
