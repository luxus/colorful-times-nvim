# File Locking for Concurrent Access in state.lua

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
