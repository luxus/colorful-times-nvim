# Planning Outline

## 1. PRD Understanding Summary
The request is to implement 14 fixes from a consolidated fix implementation plan across 5 phases (P0-P4) for the colorful-times Neovim plugin. The fixes cover:

- **Critical (P0)**: Atomic state writes, schedule caching
- **P1**: File locking, next_change_at caching, state validation
- **P2**: Config merge completeness, setup() input validation, parse_time memoization
- **P3**: Error notification standardization, magic number extraction, better io.open errors
- **P4**: EmmyLua annotations, corrupted state backups, configurable shell script

Key dependency chains:
- State storage fixes (1 → 5 → 6, 13) form one stream
- Performance/caching fixes (2 → 4, 8) form another
- Validation (5) must precede input validation (7)
- Refactoring tasks (9, 10, 11, 12, 14) can largely parallelize

## 2. Relevant Code/Docs/Resources Reviewed
**Core modules:**
- `lua/colorful-times/state.lua` - JSON persistence with non-atomic writes, incomplete merge(), no validation
- `lua/colorful-times/core.lua` - Redundant schedule.preprocess() calls, no input validation in setup()
- `lua/colorful-times/schedule.lua` - Magic number 1440, parse_time called twice per entry in preprocess()
- `lua/colorful-times/system.lua` - Inline Linux shell script, spawn_check without timeout
- `lua/colorful-times/init.lua` - Config structure with default, themes, refresh_time
- `lua/colorful-times/tui.lua` - Magic numbers (200, 5000), inconsistent error prefixes

**Tests:**
- `tests/state_spec.lua` - Documents merge() bugs with refresh_time, default, persist
- `tests/core_spec.lua` - Basic setup/toggle tests
- `tests/schedule_spec.lua` - Time parsing and schedule matching tests

## 3. Sequential Implementation Steps
1. **Implement atomic state writes (P0)** - Replace direct io.open with temp file + rename pattern
2. **Implement parsed schedule cache in core.lua (P0)** - Add module-level cache keyed by schedule content hash
3. **Implement file locking in state.lua (P1)** - Add POSIX flock-based locking around save/load
4. **Cache next_change_at results in schedule.lua (P1)** - Add memoization for repeated calls
5. **Add state validation before save in state.lua (P1)** - Validate data structure before writing
6. **Fix partial config merge in state.lua (P2)** - Extend merge() to handle refresh_time, default.*, persist
7. **Add setup() input validation in core.lua (P2)** - Type checking for all config options
8. **Memoize parse_time results in schedule.lua (P2)** - Simple string→minutes cache
9. **Standardize error notification patterns (P3)** - Ensure "colorful-times:" prefix everywhere
10. **Extract magic numbers to constants (P3)** - MINUTES_PER_DAY, DEFAULT_REFRESH_TIME, MAX_COLORSCHEMES
11. **Improve io.open error messages using vim.uv.fs_open (P3)** - Better error details for file operations
12. **Add missing EmmyLua annotations (P4)** - Document all public and internal functions
13. **Add backup for corrupted state files (P4)** - Backup to .bak when JSON parse fails
14. **Extract Linux shell script to configurable location (P4)** - Make detection script overridable

## 4. Parallelized Task Graph
### Gap Analysis

### Missing Requirements
- Cache invalidation strategy: Hash-based cache invalidation for schedule preprocessing
- File locking implementation: POSIX flock (Linux/macOS) with graceful fallback
- Validation schema: Type checking for all config fields in setup() and state validation
- Error message standardization: Consistent "colorful-times:" prefix across all notifications

### Edge Cases
- Atomic write failures: Temp file exists but rename fails, disk full during write
- Cache collisions: Hash collision for different schedule content (extremely rare, acceptable)
- Lock contention: Multiple Neovim instances competing for state.json lock
- Invalidation timing: Schedule changes during active timer callbacks

### Security Considerations
- File locking with proper permissions (0600 for temp files)
- Path traversal validation for configurable script location
- Backup file permissions matching original

### Testing Requirements
- Unit tests for atomic write operations (temp file cleanup on failure)
- Cache hit/miss tests with schedule modifications
- Concurrent access simulation for file locking
- Validation tests for invalid config types
- Corrupted state file backup verification

---

### Task 1: Atomic State Writes in state.lua

Implement atomic state file writes using temp file + rename + fsync pattern to prevent corruption on crash.

**Implementation details:**
- Modify `state.save()` to:
  1. Write to temp file (same directory as target, name: `state.json.tmp.<pid>.<random>`)
  2. fsync the temp file to ensure data reaches disk
  3. Atomic rename temp → target
  4. Clean up temp file on any error
- Handle `vim.uv.fs_*` errors properly with detailed messages
- Ensure directory creation still happens before temp file creation

**Files to modify:**
- `lua/colorful-times/state.lua` - Rewrite save() function

**Acceptance criteria:**
- State writes are atomic (either complete or not present)
- Temp files are cleaned up on success and failure
- fsync ensures durability before rename
- All existing tests pass
- New test: Simulate crash during write, verify no corruption

Dependencies: none

---

### Task 2: Cache Parsed Schedule in core.lua

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

Dependencies: none

---

### Task 3: File Locking for Concurrent Access in state.lua

Add POSIX flock-based file locking to prevent corruption when multiple Neovim instances access state.json simultaneously.

**Implementation details:**
- Implement `acquire_lock(fd, exclusive)` helper using `vim.uv.fs_flock()` (or fallback to `flock` command)
- Modify `state.save()`:
  - Open file with appropriate flags for locking
  - Acquire exclusive lock before writing
  - Release lock after close
- Modify `state.load()`:
  - Acquire shared lock for reading
  - Release after read
- Handle lock contention gracefully (retry with timeout, or fail with clear error)
- Skip locking on Windows (not supported) or when flock unavailable

**Files to modify:**
- `lua/colorful-times/state.lua` - Add locking helpers and integrate into save/load

**Acceptance criteria:**
- Multiple Neovim instances can safely read/write state concurrently
- Locks are properly released even on error
- Graceful fallback when locking unavailable
- All existing tests pass
- Add test: Simulate concurrent writes, verify no corruption

Dependencies: Task 1 (atomic writes must be in place first to avoid race conditions during lock implementation)

---

### Task 4: Cache next_change_at Results in schedule.lua

Add memoization for `next_change_at()` to avoid recalculating the same result repeatedly.

**Implementation details:**
- Add module-level cache: `_next_change_cache = { time_mins = nil, parsed_hash = nil, result = nil }`
- Modify `next_change_at(parsed, time_mins)`:
  - Compute hash of parsed schedule (can use vim.inspect or cached value from core)
  - If `time_mins == cache.time_mins` and `parsed_hash == cache.parsed_hash`, return cached result
  - Otherwise compute, store in cache, return
- Cache should be small (single entry) since time changes frequently

**Files to modify:**
- `lua/colorful-times/schedule.lua` - Add cache variable and modify next_change_at()

**Acceptance criteria:**
- Same (parsed, time_mins) pair returns cached result
- Different time or parsed schedule recomputes
- Cache cleared implicitly by replacement (not memory leak)
- All existing tests pass
- Add test: Verify caching behavior with same/different inputs

Dependencies: Task 2 (schedule caching should be in place to provide parsed_hash efficiently)

---

### Task 5: Add State Validation Before Save in state.lua

Validate data structure before writing to prevent persisting invalid state.

**Implementation details:**
- Create `validate_state(data)` function that checks:
  - `enabled` is boolean (if present)
  - `schedule` is array with valid entries (reuse schedule.validate_entry)
  - `refresh_time` is positive integer (if present)
  - `persist` is boolean (if present)
  - `default` is table with valid structure (if present)
  - `default.background` is one of "light", "dark", "system"
  - `default.colorscheme` is string
- Modify `state.save()` to call validation before writing
- Return error (don't write) if validation fails, notify user

**Files to modify:**
- `lua/colorful-times/state.lua` - Add validate_state() and integrate into save()

**Acceptance criteria:**
- Invalid state rejected with clear error message
- Valid state written successfully
- Partial state (only some fields) validates correctly
- All existing tests pass
- Add tests: Validation of invalid types, partial state, complete state

Dependencies: Task 1 (atomic writes must be in place to validate the complete write pipeline)

---

### Task 6: Fix Partial Config Merge in state.lua

Extend `merge()` to handle all config keys that can be persisted, not just `schedule` and `enabled`.

**Implementation details:**
- Modify `state.merge(base_config, stored)` to also merge:
  - `stored.refresh_time` → `result.refresh_time`
  - `stored.persist` → `result.persist`
  - `stored.default` (deep merge):
    - `stored.default.colorscheme` → `result.default.colorscheme`
    - `stored.default.background` → `result.default.background`
    - `stored.default.themes` → `result.default.themes` (deep)
- Use `vim.tbl_deep_extend("force", ...)` for default table merging
- Ensure nil values in stored don't overwrite base (preserve current nil-check pattern)
- Ensure empty tables (like `schedule = {}`) still overwrite base

**Files to modify:**
- `lua/colorful-times/state.lua` - Extend merge() function

**Acceptance criteria:**
- `refresh_time` from stored applies correctly
- `persist` from stored applies correctly
- `default.colorscheme` from stored applies correctly
- `default.background` from stored applies correctly
- `default.themes` from stored applies correctly
- Missing keys in stored don't affect base
- Empty arrays still overwrite (regression test)
- Tests in state_spec.lua that currently document BUGs should now pass

Dependencies: Task 1, Task 5 (atomic writes and validation must be in place first to ensure merge produces valid state)

---

### Task 7: Add setup() Input Validation in core.lua

Validate user input types in `setup()` to catch configuration errors early.

**Implementation details:**
- Create validation helpers or inline checks for:
  - `opts.enabled` - must be boolean if present
  - `opts.refresh_time` - must be positive integer >= 1000 if present
  - `opts.persist` - must be boolean if present
  - `opts.schedule` - must be array, each entry valid via schedule.validate_entry
  - `opts.default.background` - must be "light", "dark", or "system" if present
  - `opts.system_background_detection` - must be nil, function, or non-empty array of strings
- Validate before any merging or state loading
- Return early with `vim.notify` error if validation fails
- Don't modify config if validation fails

**Files to modify:**
- `lua/colorful-times/core.lua` - Add validation at start of setup()

**Acceptance criteria:**
- Invalid types rejected with clear error before any state changes
- Valid configuration proceeds normally
- All existing tests pass
- Add tests: Invalid enabled type, invalid refresh_time, invalid schedule entry, invalid background

Dependencies: Task 2, Task 5 (schedule caching for validation efficiency, state validation to understand validation patterns)

---

### Task 8: Memoize parse_time Results in schedule.lua

Cache `parse_time()` results to avoid re-parsing the same time strings repeatedly.

**Implementation details:**
- Add module-level cache: `_parse_time_cache = {}` (LRU not needed, small set of times)
- Modify `parse_time(str)`:
  - Check cache first: `if _parse_time_cache[str] then return _parse_time_cache[str] end`
  - Compute result, store in cache, return
- Cache nil results too (for invalid inputs) to avoid re-parsing bad data
- Optional: Add cache size limit (e.g., 100 entries) if concerned about memory

**Files to modify:**
- `lua/colorful-times/schedule.lua` - Add cache table and modify parse_time()

**Acceptance criteria:**
- Same time string returns cached result
- Invalid time string cached as nil
- Cache doesn't grow unbounded (limit or replacement strategy)
- All existing tests pass
- Add test: Verify caching, verify invalid caching

Dependencies: none (can run in parallel with other schedule.lua tasks once Task 4 is done, but independent enough to run separately)

---

### Task 9: Standardize Error Notification Patterns

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

Dependencies: none (can run in parallel with other P3 tasks)

---

### Task 10: Extract Magic Numbers to Constants

Move magic numbers to named constants for maintainability.

**Implementation details:**
- In `schedule.lua`:
  - `1440` → `MINUTES_PER_DAY = 1440`
- In `core.lua`:
  - `5000` (default refresh_time) → use `M.config.refresh_time` (already defined in init.lua)
  - `60 * 1000` (min to ms) → `MS_PER_MINUTE = 60000`
- In `tui.lua`:
  - `200` (max colorschemes) → `MAX_COLORSCHEMES = 200`
  - `0.6`, `0.8` (window ratios) could be constants but less critical
- In `init.lua`:
  - Document that `5000` is `DEFAULT_REFRESH_TIME`

**Files to modify:**
- `lua/colorful-times/schedule.lua` - Add MINUTES_PER_DAY constant
- `lua/colorful-times/core.lua` - Add MS_PER_MINUTE constant
- `lua/colorful-times/tui.lua` - Add MAX_COLORSCHEMES constant
- `lua/colorful-times/init.lua` - Add DEFAULT_REFRESH_TIME constant

**Acceptance criteria:**
- No bare magic numbers in code (except 0, 1 for indexing)
- Constants defined at module level with clear names
- All existing tests pass

Dependencies: none (can run in parallel with other P3 tasks)

---

### Task 11: Improve io.open Error Messages Using vim.uv.fs_open

Replace `io.open` with `vim.uv.fs_open` for better error information in file operations.

**Implementation details:**
- In `state.lua` `save()` and `load()`:
  - Replace `io.open(path, "w")` with `vim.uv.fs_open(path, flags, mode)`
  - Use flags: `uv.constants.O_WRONLY | uv.constants.O_CREAT | uv.constants.O_TRUNC` for save
  - Use flags: `uv.constants.O_RDONLY` for load
  - Mode: ` tonumber("644", 8)` (0644 permissions)
  - On error, `vim.uv.fs_open` returns nil + error code/name
  - Convert error codes to human-readable messages:
    - `EACCES` → "Permission denied"
    - `ENOENT` → "Directory does not exist"
    - `ENOSPC` → "Disk full"
    - `EROFS` → "Read-only filesystem"
    - etc.
- Ensure proper file descriptor closing with `vim.uv.fs_close()`

**Files to modify:**
- `lua/colorful-times/state.lua` - Replace io.open with vim.uv.fs_open in save() and load()

**Acceptance criteria:**
- Specific error messages (e.g., "Permission denied" instead of generic "could not write")
- Proper file descriptor lifecycle management
- Atomic write compatibility (Task 1 uses uv.fs_* functions already)
- All existing tests pass

Dependencies: Task 1 (atomic writes already implement uv.fs_* pattern, this completes the migration)

---

### Task 12: Add Missing EmmyLua Annotations to Undocumented Functions

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

Dependencies: none (can run in parallel with other P4 tasks, or after main implementation to annotate final code)

---

### Task 13: Add Backup for Corrupted State Files

When `state.load()` encounters a parse error, backup the corrupted file before returning empty state.

**Implementation details:**
- Modify `state.load()` error handling:
  - When `pcall(vim.json.decode)` fails:
    1. Generate backup path: `path .. ".bak." .. os.time()`
    2. Use `vim.uv.fs_rename(path, backup)` to move corrupted file to backup
    3. If rename fails, try copy+delete fallback
    4. Notify user: "colorful-times: corrupted state backed up to <path>"
  5. Return empty table as before
- Keep only last N backups (optional cleanup, e.g., keep last 5)
- Ensure backup doesn't overwrite existing (use timestamp)

**Files to modify:**
- `lua/colorful-times/state.lua` - Add backup logic to load() error handler

**Acceptance criteria:**
- Corrupted state file preserved with .bak.<timestamp> suffix
- User notified of backup location
- Fresh empty state returned for new configuration
- Multiple corruptions create multiple backups
- All existing tests pass
- Add test: Simulate corruption, verify backup created

Dependencies: Task 1, Task 5 (atomic writes and validation in place to understand state lifecycle)

---

### Task 14: Extract Linux Shell Script to Configurable Location

Make the inline Linux detection script configurable instead of hardcoded.

**Implementation details:**
- In `init.lua`, add new config option:
  - `system_background_detection_script` - string path to custom script or nil for default
- In `system.lua` `get_background()`:
  - Check if `config.system_background_detection_script` is set
  - If set, execute that script instead of inline script: `spawn_check("sh", { "-c", config.system_background_detection_script or default_script }, ...)`
  - If not set, use current inline script as default
- Document the script interface: exit 0 for dark, exit 1 for light
- Ensure script validation (file exists, executable) with clear error if invalid

**Files to modify:**
- `lua/colorful-times/init.lua` - Add system_background_detection_script to config
- `lua/colorful-times/system.lua` - Use configurable script or default inline script
- `doc/colorful-times.txt` - Document new config option

**Acceptance criteria:**
- Default behavior unchanged (inline script used)
- Custom script path respected when provided
- Proper error handling for missing/non-executable scripts
- All existing tests pass
- Add test: Verify custom script execution, verify fallback to default

Dependencies: none (can run in parallel with other P4 tasks)

---

```tasks-json
[
  {
    "title": "Atomic State Writes in state.lua",
    "description": "Implement atomic state file writes using temp file + rename + fsync pattern to prevent corruption on crash.\n\n**Implementation details:**\n- Modify `state.save()` to:\n  1. Write to temp file (same directory as target, name: `state.json.tmp.<pid>.<random>`)\n  2. fsync the temp file to ensure data reaches disk\n  3. Atomic rename temp → target\n  4. Clean up temp file on any error\n- Handle `vim.uv.fs_*` errors properly with detailed messages\n- Ensure directory creation still happens before temp file creation\n\n**Files to modify:**\n- `lua/colorful-times/state.lua` - Rewrite save() function\n\n**Acceptance criteria:**\n- State writes are atomic (either complete or not present)\n- Temp files are cleaned up on success and failure\n- fsync ensures durability before rename\n- All existing tests pass\n- New test: Simulate crash during write, verify no corruption",
    "dependsOn": [],
    "skills": []
  },
  {
    "title": "Cache Parsed Schedule in core.lua",
    "description": "Add module-level cache for `schedule.preprocess()` results to eliminate redundant parsing.\n\n**Implementation details:**\n- Add `_schedule_cache = { hash = nil, parsed = nil, default_bg = nil }` at module level\n- Create `get_cached_schedule(config_schedule, default_bg)` helper:\n  - Compute simple hash of schedule array (e.g., vim.inspect or serialization)\n  - Return cached result if hash matches, otherwise preprocess and cache\n- Replace all 4 calls to `schedule.preprocess()` in core.lua with cached version:\n  - `resolve_theme()` \n  - `arm_schedule_timer()`\n  - `needs_system_poll()`\n  - `reload()` (already calls preprocess, ensure it clears cache)\n\n**Files to modify:**\n- `lua/colorful-times/core.lua` - Add cache module variable and helper function\n\n**Acceptance criteria:**\n- schedule.preprocess() called only once per unique schedule\n- Cache invalidates when schedule changes\n- Cache clears on reload()\n- No memory leaks (cache replaced, not accumulated)\n- All existing tests pass\n- Add test: Verify preprocess called once for multiple core operations",
    "dependsOn": [],
    "skills": []
  },
  {
    "title": "File Locking for Concurrent Access in state.lua",
    "description": "Add POSIX flock-based file locking to prevent corruption when multiple Neovim instances access state.json simultaneously.\n\n**Implementation details:**\n- Implement `acquire_lock(fd, exclusive)` helper using `vim.uv.fs_flock()` (or fallback to `flock` command)\n- Modify `state.save()`:\n  - Open file with appropriate flags for locking\n  - Acquire exclusive lock before writing\n  - Release lock after close\n- Modify `state.load()`:\n  - Acquire shared lock for reading\n  - Release after read\n- Handle lock contention gracefully (retry with timeout, or fail with clear error)\n- Skip locking on Windows (not supported) or when flock unavailable\n\n**Files to modify:**\n- `lua/colorful-times/state.lua` - Add locking helpers and integrate into save/load\n\n**Acceptance criteria:**\n- Multiple Neovim instances can safely read/write state concurrently\n- Locks are properly released even on error\n- Graceful fallback when locking unavailable\n- All existing tests pass\n- Add test: Simulate concurrent writes, verify no corruption",
    "dependsOn": ["Atomic State Writes in state.lua"],
    "skills": []
  },
  {
    "title": "Cache next_change_at Results in schedule.lua",
    "description": "Add memoization for `next_change_at()` to avoid recalculating the same result repeatedly.\n\n**Implementation details:**\n- Add module-level cache: `_next_change_cache = { time_mins = nil, parsed_hash = nil, result = nil }`\n- Modify `next_change_at(parsed, time_mins)`:\n  - Compute hash of parsed schedule (can use vim.inspect or cached value from core)\n  - If `time_mins == cache.time_mins` and `parsed_hash == cache.parsed_hash`, return cached result\n  - Otherwise compute, store in cache, return\n- Cache should be small (single entry) since time changes frequently\n\n**Files to modify:**\n- `lua/colorful-times/schedule.lua` - Add cache variable and modify next_change_at()\n\n**Acceptance criteria:**\n- Same (parsed, time_mins) pair returns cached result\n- Different time or parsed schedule recomputes\n- Cache cleared implicitly by replacement (not memory leak)\n- All existing tests pass\n- Add test: Verify caching behavior with same/different inputs",
    "dependsOn": ["Cache Parsed Schedule in core.lua"],
    "skills": []
  },
  {
    "title": "Add State Validation Before Save in state.lua",
    "description": "Validate data structure before writing to prevent persisting invalid state.\n\n**Implementation details:**\n- Create `validate_state(data)` function that checks:\n  - `enabled` is boolean (if present)\n  - `schedule` is array with valid entries (reuse schedule.validate_entry)\n  - `refresh_time` is positive integer (if present)\n  - `persist` is boolean (if present)\n  - `default` is table with valid structure (if present)\n  - `default.background` is one of \"light\", \"dark\", \"system\"\n  - `default.colorscheme` is string\n- Modify `state.save()` to call validation before writing\n- Return error (don't write) if validation fails, notify user\n\n**Files to modify:**\n- `lua/colorful-times/state.lua` - Add validate_state() and integrate into save()\n\n**Acceptance criteria:**\n- Invalid state rejected with clear error message\n- Valid state written successfully\n- Partial state (only some fields) validates correctly\n- All existing tests pass\n- Add tests: Validation of invalid types, partial state, complete state",
    "dependsOn": ["Atomic State Writes in state.lua"],
    "skills": []
  },
  {
    "title": "Fix Partial Config Merge in state.lua",
    "description": "Extend `merge()` to handle all config keys that can be persisted, not just `schedule` and `enabled`.\n\n**Implementation details:**\n- Modify `state.merge(base_config, stored)` to also merge:\n  - `stored.refresh_time` → `result.refresh_time`\n  - `stored.persist` → `result.persist`\n  - `stored.default` (deep merge):\n    - `stored.default.colorscheme` → `result.default.colorscheme`\n    - `stored.default.background` → `result.default.background`\n    - `stored.default.themes` → `result.default.themes` (deep)\n- Use `vim.tbl_deep_extend(\"force\", ...)` for default table merging\n- Ensure nil values in stored don't overwrite base (preserve current nil-check pattern)\n- Ensure empty tables (like `schedule = {}`) still overwrite base\n\n**Files to modify:**\n- `lua/colorful-times/state.lua` - Extend merge() function\n\n**Acceptance criteria:**\n- `refresh_time` from stored applies correctly\n- `persist` from stored applies correctly\n- `default.colorscheme` from stored applies correctly\n- `default.background` from stored applies correctly\n- `default.themes` from stored applies correctly\n- Missing keys in stored don't affect base\n- Empty arrays still overwrite (regression test)\n- Tests in state_spec.lua that currently document BUGs should now pass",
    "dependsOn": ["Atomic State Writes in state.lua", "Add State Validation Before Save in state.lua"],
    "skills": []
  },
  {
    "title": "Add setup() Input Validation in core.lua",
    "description": "Validate user input types in `setup()` to catch configuration errors early.\n\n**Implementation details:**\n- Create validation helpers or inline checks for:\n  - `opts.enabled` - must be boolean if present\n  - `opts.refresh_time` - must be positive integer >= 1000 if present\n  - `opts.persist` - must be boolean if present\n  - `opts.schedule` - must be array, each entry valid via schedule.validate_entry\n  - `opts.default.background` - must be \"light\", \"dark\", or \"system\" if present\n  - `opts.system_background_detection` - must be nil, function, or non-empty array of strings\n- Validate before any merging or state loading\n- Return early with `vim.notify` error if validation fails\n- Don't modify config if validation fails\n\n**Files to modify:**\n- `lua/colorful-times/core.lua` - Add validation at start of setup()\n\n**Acceptance criteria:**\n- Invalid types rejected with clear error before any state changes\n- Valid configuration proceeds normally\n- All existing tests pass\n- Add tests: Invalid enabled type, invalid refresh_time, invalid schedule entry, invalid background",
    "dependsOn": ["Cache Parsed Schedule in core.lua", "Add State Validation Before Save in state.lua"],
    "skills": []
  },
  {
    "title": "Memoize parse_time Results in schedule.lua",
    "description": "Cache `parse_time()` results to avoid re-parsing the same time strings repeatedly.\n\n**Implementation details:**\n- Add module-level cache: `_parse_time_cache = {}` (LRU not needed, small set of times)\n- Modify `parse_time(str)`:\n  - Check cache first: `if _parse_time_cache[str] then return _parse_time_cache[str] end`\n  - Compute result, store in cache, return\n- Cache nil results too (for invalid inputs) to avoid re-parsing bad data\n- Optional: Add cache size limit (e.g., 100 entries) if concerned about memory\n\n**Files to modify:**\n- `lua/colorful-times/schedule.lua` - Add cache table and modify parse_time()\n\n**Acceptance criteria:**\n- Same time string returns cached result\n- Invalid time string cached as nil\n- Cache doesn't grow unbounded (limit or replacement strategy)\n- All existing tests pass\n- Add test: Verify caching, verify invalid caching",
    "dependsOn": ["Cache next_change_at Results in schedule.lua"],
    "skills": []
  },
  {
    "title": "Standardize Error Notification Patterns",
    "description": "Ensure all error notifications use \"colorful-times:\" prefix consistently.\n\n**Implementation details:**\n- Audit all `vim.notify` calls across all modules:\n  - `state.lua`: \"colorful-times: failed to parse state file\", \"colorful-times: could not write state file\"\n  - `schedule.lua`: \"colorful-times: invalid schedule entry %d: %s\"\n  - `core.lua`: \"colorful-times: failed to apply colorscheme '%s': %s\", \"colorful-times: enabled\", \"colorful-times: disabled\"\n  - `tui.lua`: \"Invalid time: '%s' (use HH:MM)\", \"colorful-times: config reloaded\"\n- Fix missing prefixes:\n  - tui.lua: \"Invalid time\" → \"colorful-times: invalid time\"\n  - Any other generic messages\n- Create helper `notify(msg, level)` in each module if needed for consistency\n\n**Files to modify:**\n- `lua/colorful-times/tui.lua` - Add prefix to user-facing errors\n- Any other files with inconsistent prefixes\n\n**Acceptance criteria:**\n- All error/warning/info messages prefixed with \"colorful-times:\"\n- Consistent capitalization and formatting\n- All existing tests pass",
    "dependsOn": [],
    "skills": []
  },
  {
    "title": "Extract Magic Numbers to Constants",
    "description": "Move magic numbers to named constants for maintainability.\n\n**Implementation details:**\n- In `schedule.lua`:\n  - `1440` → `MINUTES_PER_DAY = 1440`\n- In `core.lua`:\n  - `5000` (default refresh_time) → use `M.config.refresh_time` (already defined in init.lua)\n  - `60 * 1000` (min to ms) → `MS_PER_MINUTE = 60000`\n- In `tui.lua`:\n  - `200` (max colorschemes) → `MAX_COLORSCHEMES = 200`\n  - `0.6`, `0.8` (window ratios) could be constants but less critical\n- In `init.lua`:\n  - Document that `5000` is `DEFAULT_REFRESH_TIME`\n\n**Files to modify:**\n- `lua/colorful-times/schedule.lua` - Add MINUTES_PER_DAY constant\n- `lua/colorful-times/core.lua` - Add MS_PER_MINUTE constant\n- `lua/colorful-times/tui.lua` - Add MAX_COLORSCHEMES constant\n- `lua/colorful-times/init.lua` - Add DEFAULT_REFRESH_TIME constant\n\n**Acceptance criteria:**\n- No bare magic numbers in code (except 0, 1 for indexing)\n- Constants defined at module level with clear names\n- All existing tests pass",
    "dependsOn": [],
    "skills": []
  },
  {
    "title": "Improve io.open Error Messages Using vim.uv.fs_open",
    "description": "Replace `io.open` with `vim.uv.fs_open` for better error information in file operations.\n\n**Implementation details:**\n- In `state.lua` `save()` and `load()`:\n  - Replace `io.open(path, \"w\")` with `vim.uv.fs_open(path, flags, mode)`\n  - Use flags: `uv.constants.O_WRONLY | uv.constants.O_CREAT | uv.constants.O_TRUNC` for save\n  - Use flags: `uv.constants.O_RDONLY` for load\n  - Mode: ` tonumber(\"644\", 8)` (0644 permissions)\n  - On error, `vim.uv.fs_open` returns nil + error code/name\n  - Convert error codes to human-readable messages:\n    - `EACCES` → \"Permission denied\"\n    - `ENOENT` → \"Directory does not exist\"\n    - `ENOSPC` → \"Disk full\"\n    - `EROFS` → \"Read-only filesystem\"\n    - etc.\n- Ensure proper file descriptor closing with `vim.uv.fs_close()`\n\n**Files to modify:**\n- `lua/colorful-times/state.lua` - Replace io.open with vim.uv.fs_open in save() and load()\n\n**Acceptance criteria:**\n- Specific error messages (e.g., \"Permission denied\" instead of generic \"could not write\")\n- Proper file descriptor lifecycle management\n- Atomic write compatibility (Task 1 uses uv.fs_* functions already)\n- All existing tests pass",
    "dependsOn": ["Atomic State Writes in state.lua"],
    "skills": []
  },
  {
    "title": "Add Missing EmmyLua Annotations to Undocumented Functions",
    "description": "Add complete EmmyLua annotations to all functions lacking documentation.\n\n**Implementation details:**\n- Audit all functions in all modules for missing annotations:\n  - `state.lua`: `path()`, `load()`, `save()`, `merge()` - some missing return type details\n  - `core.lua`: Many internal functions lack annotations (`stop_timer`, `now_mins`, `resolve_theme`, `set_colorscheme`, `arm_schedule_timer`, `needs_system_poll`, `start_poll_timer`, `register_focus_autocmds`, `enable_plugin`, `disable_plugin`)\n  - `schedule.lua`: All functions have annotations ✓\n  - `system.lua`: `sysname()` has annotation, `spawn_check` and `get_background` lack param details\n  - `tui.lua`: Many internal functions lack annotations (`has_snacks`, `pad`, `render`, `prompt_time`, `pick_colorscheme`, `entry_form`, all action_* functions, `cursor_move`, `close`, `open`)\n  - `init.lua`: Config class annotations are good ✓\n- Add `---@param`, `---@return`, `---@class` as needed\n- Follow existing code style from AGENTS.md\n\n**Files to modify:**\n- `lua/colorful-times/state.lua` - Complete any partial annotations\n- `lua/colorful-times/core.lua` - Add annotations to all internal functions\n- `lua/colorful-times/system.lua` - Complete param annotations\n- `lua/colorful-times/tui.lua` - Add annotations to all internal functions\n\n**Acceptance criteria:**\n- All public functions have complete EmmyLua annotations\n- All internal functions have annotations where type information adds value\n- No regressions in functionality\n- All existing tests pass",
    "dependsOn": [],
    "skills": []
  },
  {
    "title": "Add Backup for Corrupted State Files",
    "description": "When `state.load()` encounters a parse error, backup the corrupted file before returning empty state.\n\n**Implementation details:**\n- Modify `state.load()` error handling:\n  - When `pcall(vim.json.decode)` fails:\n    1. Generate backup path: `path .. \".bak.\" .. os.time()`\n    2. Use `vim.uv.fs_rename(path, backup)` to move corrupted file to backup\n    3. If rename fails, try copy+delete fallback\n    4. Notify user: \"colorful-times: corrupted state backed up to <path>\"\n  5. Return empty table as before\n- Keep only last N backups (optional cleanup, e.g., keep last 5)\n- Ensure backup doesn't overwrite existing (use timestamp)\n\n**Files to modify:**\n- `lua/colorful-times/state.lua` - Add backup logic to load() error handler\n\n**Acceptance criteria:**\n- Corrupted state file preserved with .bak.<timestamp> suffix\n- User notified of backup location\n- Fresh empty state returned for new configuration\n- Multiple corruptions create multiple backups\n- All existing tests pass\n- Add test: Simulate corruption, verify backup created",
    "dependsOn": ["Atomic State Writes in state.lua", "Add State Validation Before Save in state.lua"],
    "skills": []
  },
  {
    "title": "Extract Linux Shell Script to Configurable Location",
    "description": "Make the inline Linux detection script configurable instead of hardcoded.\n\n**Implementation details:**\n- In `init.lua`, add new config option:\n  - `system_background_detection_script` - string path to custom script or nil for default\n- In `system.lua` `get_background()`:\n  - Check if `config.system_background_detection_script` is set\n  - If set, execute that script instead of inline script: `spawn_check(\"sh\", { \"-c\", config.system_background_detection_script or default_script }, ...)`\n  - If not set, use current inline script as default\n- Document the script interface: exit 0 for dark, exit 1 for light\n- Ensure script validation (file exists, executable) with clear error if invalid\n\n**Files to modify:**\n- `lua/colorful-times/init.lua` - Add system_background_detection_script to config\n- `lua/colorful-times/system.lua` - Use configurable script or default inline script\n- `doc/colorful-times.txt` - Document new config option\n\n**Acceptance criteria:**\n- Default behavior unchanged (inline script used)\n- Custom script path respected when provided\n- Proper error handling for missing/non-executable scripts\n- All existing tests pass\n- Add test: Verify custom script execution, verify fallback to default",
    "dependsOn": [],
    "skills": []
  }
]
```
