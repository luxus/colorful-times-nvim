# Future Optimization Ideas

## ✅ Completed

- ~~Cache preprocessed schedule in core.lua~~ - DONE (experiment #3)
- ~~Optimized schedule cache with LRU eviction~~ - DONE (experiment #2)
- ~~O(1) key lookups for lazy loading~~ - DONE (experiment #4)
- ~~Static lookup tables for validation~~ - DONE (experiments #5, #8, #12)
- ~~Cache snacks detection~~ - DONE (experiment #7)
- ~~Cache colorscheme list in TUI~~ - DONE (experiment #11)
- ~~Cache next_change_at results~~ - DONE (experiment #8)
- ~~Use vim.uv.now() for time~~ - DONE (experiment #10)
- ~~Use cached schedule in arm_schedule_timer~~ - DONE (experiment #9)

## 🔄 Remaining Ideas

### Performance Ideas

1. **Batch state writes**: Currently state is saved immediately on every TUI change. Could debounce/batch writes to reduce disk I/O.

2. **Incremental schedule validation**: When editing a single entry, only validate that entry instead of the whole schedule.

3. **Precompute boundary table**: For `next_change_at`, could precompute a sorted list of all unique boundaries once instead of iterating all entries every call. Complexity: O(n) → O(log n) for large schedules.

4. **Timer coalescing**: When schedule timer and poll timer would fire close together, coalesce into single timer.

5. **Memory pool for parsed entries**: For very large schedules (>100 entries), use object pooling to reduce GC pressure.

6. **Freeze config after setup**: Make config table read-only after setup() to prevent accidental mutations.

### Code Quality Ideas

1. **Type-safe config merging**: Use stricter types for config merging to catch errors at edit time.

2. **Async state persistence**: Make state save fire-and-forget async with error callback.

3. **Plugin API for custom themes**: Allow users to register custom theme providers.

4. **Fuzzy schedule matching**: Support "sunrise"/"sunset" keywords that resolve to actual times.

5. **Profile-guided optimization**: Add instrumentation to measure actual hot paths in production use.
