# Memoize parse_time Results in schedule.lua

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
