# Planning Progress

## Notes
<!-- User notes here are read by the planner on every run.
     Add steering like "ignore auth" or "prioritize performance". -->


---
## Run: 2026-03-28T05:42:33.238Z — Scan the codebase for bugs, and search for improvements o...

### Pass 1 (05:43)
Now I have a comprehensive understanding of the codebase. Let me produce the task breakdown.

## 1. PRD Understanding Summary

The request is to **scan the codebase for bugs and identify improvements/refactors** for the colorful-times Neovim plugin. This is a codebase audit task rather than a feature implementation.

Key areas to investigate:
- **Logic bugs** in schedule parsing, time calculations, state management
- **Performance issues** like redundant calculations
- **Error handling gaps** (missing pcall, no timeouts, unvalidated inputs)
- **Edge cases** (overnight schedules, empty schedules, concurrent access)
- **Code quality** (caching, DRY violations, inconsistent patterns)

## 2. Relevant Code/Docs/Resources Reviewed

**Core modules analyzed:**
- `lua/colorful-times/init.lua` - Plugin root with metatable lazy-loading
- `lua/colorful-times/core.lua` - Main timer/colorscheme logic
- `lua/colorful-times/schedule.lua` - Time parsing and schedule matching
- `lua/colorful-times/state.lua` - JSON persistence
- `lua/colorful-times/system.lua` - OS background detection
- `lua/colorful-times/tui.lua` - Interactive UI
- `lua/colorful-times/health.lua` - :checkhealth implementation
- `plugin/colorful-times.lua` - Command registration

**Test files reviewed:**
- `tests/core_spec.lua`, `schedule_spec.lua`, `state_spec.lua`, `system_spec.lua`
- `tests/minimal_init.vim` - plenary.nvim test setup

**Documentation:**
- `doc/colorful-times.txt` - Vim help documentation
- `AGENTS.md` - Project coding conventions and architecture

## 3. Sequential Implementation Steps

1. **Audit core.lua for timer/state bugs** - Check uninitialized `_previous_bg`, timer lifecycle edge cases, focus state tracking
2. **Audit schedule.lua for time logic bugs** - Validate `next_change_at` overnight wrapping, time parsing edge cases, overlap detection
3. **Audit system.lua for subprocess issues** - Check for missing timeouts, error handling, command validation
4. **Audit tui.lua for UI/UX bugs** - Check colorscheme restore on cancel, buffer validation, cursor bounds
5. **Audit state.lua for persistence bugs** - Check file locking, atomic writes, concurrent access handling
6. **Identify performance improvements** - Cache schedule preprocessing, reduce redundant calculations
7. **Identify refactoring opportunities** - Consolidate duplicate patterns, improve error handling consistency, add validation
8. **Create fix implementation plan** - Prioritize critical bugs, document safe refactors

## 4. Parallelized Task Graph

### Gap Analysis

### Missing Requirements
- Schedule entry overlap detection (current code allows conflicting entries)
- Colorscheme existence validation (health check doesn't verify colorschemes exist)
- Input validation for `setup()` options (no validation of user config)
- Timer cleanup on plugin unload/reload edge cases

### Edge Cases
- Empty schedule with no default theme configuration
- Rapid toggle on/off could leave timers in inconsistent state
- Colorscheme picker cancel doesn't always restore original theme
- `next_change_at` calculation for overnight schedules wrapping past midnight
- Concurrent state.json writes from multiple Neovim instances
- System background detection when command doesn't exist (hanging subprocess)

### Security Considerations
- `system_background_detection` accepts arbitrary command tables - could execute malicious commands
- State file path isn't validated for path traversal
- Shell script in Linux detection uses unsanitized environment variables

### Testing Requirements
- Timer lifecycle tests (start/stop/cleanup)
- Concurrent state access simulation
- Overnight schedule boundary tests
- Error injection for subprocess failures
- Colorscheme picker cancel/confirm flows

---

### Task 1: Audit core.lua for Timer and State Bugs

Review `core.lua` for critical bugs in timer lifecycle and state management:

**Bugs to verify:**
- `_previous_bg` used before initialization in `resolve_theme()` fallback chain
- `stop_timer()` doesn't check if timer is active before stopping
- `needs_system_poll()` calls `preprocess()` on every poll tick (every 5s by default) - inefficient
- No cleanup of autocmds when plugin disabled
- Focus state `_focused` initialized to `true` but actual focus state unknown at startup

**Acceptance criteria:**
- Document all confirmed bugs with line numbers
- Identify performance hotspots
- Note missing cleanup patterns
- Provide fix recommendations

Dependencies: none

---

### Task 2: Audit schedule.lua for Time Logic Bugs

Review `schedule.lua` for bugs in time parsing and schedule matching:

**Bugs to verify:**
- `next_change_at()` overnight boundary calculation - when current time is 23:00 and next boundary is 01:00, the diff wraps incorrectly
- Time parsing accepts invalid formats like "12:5" (single-digit minute)
- No overlap detection between schedule entries
- `preprocess()` calls `parse_time()` twice per entry (validate then parse again)

**Acceptance criteria:**
- Verify `next_change_at` behavior with overnight test cases
- Document time parsing edge cases
- Identify missing validation (overlaps, invalid colorschemes)
- Note performance inefficiencies

Dependencies: none

---

### Task 3: Audit system.lua for Subprocess and Detection Bugs

Review `system.lua` for bugs in OS background detection:

**Bugs to verify:**
- No timeout on `uv.spawn()` - subprocess could hang indefinitely
- `spawn_check()` doesn't validate command exists before spawning
- Shell script for Linux has complex quote escaping that could fail
- No handling for `kreadconfig` returning non-standard output
- stderr/stdout readers drain but don't handle read errors

**Acceptance criteria:**
- Document timeout and hanging risks
- Identify missing error handling for spawn failures
- Note platform-specific edge cases
- Provide safe timeout implementation approach

Dependencies: none

---

### Task 4: Audit tui.lua for UI and Interaction Bugs

Review `tui.lua` for bugs in the interactive schedule manager:

**Bugs to verify:**
- `pick_colorscheme()` snacks picker doesn't always restore original colorscheme on cancel
- `render()` doesn't validate `_state.buf` is still valid before all operations
- `action_delete()` doesn't re-validate entry exists after async confirmation
- `cursor_move()` allows invalid cursor positions when schedule is empty
- `save_and_reload()` calls both `core.reload()` and `render()` - potential redundant operations

**Acceptance criteria:**
- Document UI state consistency issues
- Identify async race conditions
- Note missing validation checks
- Provide fixes for colorscheme restore flow

Dependencies: none

---

### Task 5: Audit state.lua for Persistence Bugs

Review `state.lua` for bugs in JSON persistence:

**Bugs to verify:**
- No file locking for concurrent access (multiple Neovim instances)
- `io.open` failures don't provide detailed error information
- `state.save()` writes non-atomically (could corrupt on crash)
- No validation of data before saving (could persist invalid state)
- `merge()` only handles `schedule` and `enabled` - ignores other config keys that might be persisted

**Acceptance criteria:**
- Document concurrent access risks
- Identify atomic write issues
- Note missing validation
- Provide safe atomic write approach

Dependencies: none

---

### Task 6: Identify Performance Improvements

Analyze codebase for performance optimization opportunities:

**Areas to improve:**
- Cache parsed schedule results instead of calling `preprocess()` repeatedly
- Cache `sysname()` result (already done, verify it works)
- Avoid recalculating `next_change_at()` on every poll when schedule hasn't changed
- Lazy-load modules more aggressively (health.lua, tui.lua already lazy - verify others)
- Reduce `vim.schedule()` calls by batching operations

**Acceptance criteria:**
- Document all redundant calculations
- Identify caching opportunities
- Note hot paths that need optimization
- Provide implementation priority ranking

Dependencies: Task 1 (core.lua hotspots), Task 2 (schedule preprocessing)

---

### Task 7: Identify Refactoring and Code Quality Improvements

Analyze codebase for maintainability improvements:

**Refactor opportunities:**
- Consolidate error notification patterns (some use `vim.notify`, some don't)
- Extract magic numbers (1440 minutes/day, 5000ms refresh)
- Add EmmyLua annotations to undocumented functions
- Standardize `pcall` error handling patterns
- Add input validation for `setup()` options
- Extract shell script for Linux detection to configurable location

**Acceptance criteria:**
- Document inconsistent patterns
- Identify code duplication
- Note missing type annotations
- Provide safe refactoring priority list

Dependencies: Task 1, Task 2, Task 3, Task 4, Task 5 (all audit results)

---

### Task 8: Create Consolidated Fix Implementation Plan

Synthesize all audit findings into a prioritized fix plan:

**Deliverables:**
- Categorized bug list (critical, major, minor)
- Performance improvement roadmap
- Refactoring priority matrix
- Estimated effort for each fix
- Safe ordering for implementation (dependencies between fixes)

**Acceptance criteria:**
- All bugs from Tasks 1-5 documented with severity
- Performance improvements from Task 6 prioritized
- Refactors from Task 7 sequenced by safety
- Clear implementation order that respects dependencies

Dependencies: Task 1, Task 2, Task 3, Task 4, Task 5, Task 6, Task 7

```tasks-json
[
  {
    "title": "Audit core.lua for Timer and State Bugs",
    "description": "Review core.lua for critical bugs in timer lifecycle and state management:\n\n**Bugs to verify:**\n- `_previous_bg` used before initialization in `resolve_theme()` fallback chain\n- `stop_timer()` doesn't check if timer is active before stopping\n- `needs_system_poll()` calls `preprocess()` on every poll tick (every 5s by default) - inefficient\n- No cleanup of autocmds when plugin disabled\n- Focus state `_focused` initialized to `true` but actual focus state unknown at startup\n\n**Acceptance criteria:**\n- Document all confirmed bugs with line numbers\n- Identify performance hotspots\n- Note missing cleanup patterns\n- Provide fix recommendations",
    "dependsOn": [],
    "skills": []
  },
  {
    "title": "Audit schedule.lua for Time Logic Bugs",
    "description": "Review schedule.lua for bugs in time parsing and schedule matching:\n\n**Bugs to verify:**\n- `next_change_at()` overnight boundary calculation - when current time is 23:00 and next boundary is 01:00, the diff wraps incorrectly\n- Time parsing accepts invalid formats like \"12:5\" (single-digit minute)\n- No overlap detection between schedule entries\n- `preprocess()` calls `parse_time()` twice per entry (validate then parse again)\n\n**Acceptance criteria:**\n- Verify `next_change_at` behavior with overnight test cases\n- Document time parsing edge cases\n- Identify missing validation (overlaps, invalid colorschemes)\n- Note performance inefficiencies",
    "dependsOn": [],
    "skills": []
  },
  {
    "title": "Audit system.lua for Subprocess and Detection Bugs",
    "description": "Review system.lua for bugs in OS background detection:\n\n**Bugs to verify:**\n- No timeout on `uv.spawn()` - subprocess could hang indefinitely\n- `spawn_check()` doesn't validate command exists before spawning\n- Shell script for Linux has complex quote escaping that could fail\n- No handling for `kreadconfig` returning non-standard output\n- stderr/stdout readers drain but don't handle read errors\n\n**Acceptance criteria:**\n- Document timeout and hanging risks\n- Identify missing error handling for spawn failures\n- Note platform-specific edge cases\n- Provide safe timeout implementation approach",
    "dependsOn": [],
    "skills": []
  },
  {
    "title": "Audit tui.lua for UI and Interaction Bugs",
    "description": "Review tui.lua for bugs in the interactive schedule manager:\n\n**Bugs to verify:**\n- `pick_colorscheme()` snacks picker doesn't always restore original colorscheme on cancel\n- `render()` doesn't validate `_state.buf` is still valid before all operations\n- `action_delete()` doesn't re-validate entry exists after async confirmation\n- `cursor_move()` allows invalid cursor positions when schedule is empty\n- `save_and_reload()` calls both `core.reload()` and `render()` - potential redundant operations\n\n**Acceptance criteria:**\n- Document UI state consistency issues\n- Identify async race conditions\n- Note missing validation checks\n- Provide fixes for colorscheme restore flow",
    "dependsOn": [],
    "skills": []
  },
  {
    "title": "Audit state.lua for Persistence Bugs",
    "description": "Review state.lua for bugs in JSON persistence:\n\n**Bugs to verify:**\n- No file locking for concurrent access (multiple Neovim instances)\n- `io.open` failures don't provide detailed error information\n- `state.save()` writes non-atomically (could corrupt on crash)\n- No validation of data before saving (could persist invalid state)\n- `merge()` only handles `schedule` and `enabled` - ignores other config keys that might be persisted\n\n**Acceptance criteria:**\n- Document concurrent access risks\n- Identify atomic write issues\n- Note missing validation\n- Provide safe atomic write approach",
    "dependsOn": [],
    "skills": []
  },
  {
    "title": "Identify Performance Improvements",
    "description": "Analyze codebase for performance optimization opportunities:\n\n**Areas to improve:**\n- Cache parsed schedule results instead of calling `preprocess()` repeatedly\n- Cache `sysname()` result (already done, verify it works)\n- Avoid recalculating `next_change_at()` on every poll when schedule hasn't changed\n- Lazy-load modules more aggressively (health.lua, tui.lua already lazy - verify others)\n- Reduce `vim.schedule()` calls by batching operations\n\n**Acceptance criteria:**\n- Document all redundant calculations\n- Identify caching opportunities\n- Note hot paths that need optimization\n- Provide implementation priority ranking",
    "dependsOn": ["Audit core.lua for Timer and State Bugs", "Audit schedule.lua for Time Logic Bugs"],
    "skills": []
  },
  {
    "title": "Identify Refactoring and Code Quality Improvements",
    "description": "Analyze codebase for maintainability improvements:\n\n**Refactor opportunities:**\n- Consolidate error notification patterns (some use `vim.notify`, some don't)\n- Extract magic numbers (1440 minutes/day, 5000ms refresh)\n- Add EmmyLua annotations to undocumented functions\n- Standardize `pcall` error handling patterns\n- Add input validation for `setup()` options\n- Extract shell script for Linux detection to configurable location\n\n**Acceptance criteria:**\n- Document inconsistent patterns\n- Identify code duplication\n- Note missing type annotations\n- Provide safe refactoring priority list",
    "dependsOn": ["Audit core.lua for Timer and State Bugs", "Audit schedule.lua for Time Logic Bugs", "Audit system.lua for Subprocess and Detection Bugs", "Audit tui.lua for UI and Interaction Bugs", "Audit state.lua for Persistence Bugs"],
    "skills": []
  },
  {
    "title": "Create Consolidated Fix Implementation Plan",
    "description": "Synthesize all audit findings into a prioritized fix plan:\n\n**Deliverables:**\n- Categorized bug list (critical, major, minor)\n- Performance improvement roadmap\n- Refactoring priority matrix\n- Estimated effort for each fix\n- Safe ordering for implementation (dependencies between fixes)\n\n**Acceptance criteria:**\n- All bugs from audit tasks documented with severity\n- Performance improvements prioritized\n- Refactors sequenced by safety\n- Clear implementation order that respects dependencies",
    "dependsOn": ["Audit core.lua for Timer and State Bugs", "Audit schedule.lua for Time Logic Bugs", "Audit system.lua for Subprocess and Detection Bugs", "Audit tui.lua for UI and Interaction Bugs", "Audit state.lua for Persistence Bugs", "Identify Performance Improvements", "Identify Refactoring and Code Quality Improvements"],
    "skills": ["visual-explainer"]
  }
]
```

---
## Run: 2026-03-28T05:49:08.325Z — Implement all fixes from the consolidated fix implementat...

### Pass 1 (05:50)
Now I have a complete understanding of the codebase. Let me produce the comprehensive task breakdown for the consolidated fix implementation plan.

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
