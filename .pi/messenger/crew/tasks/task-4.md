# Cache next_change_at Results in schedule.lua

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
