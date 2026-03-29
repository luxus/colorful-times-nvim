# Future Optimization Ideas

## ✅ Completed (14 optimizations)

| # | Optimization | Location | Impact |
|---|--------------|----------|--------|
| 1 | Cache preprocessed schedule | core.lua | Reduces parsing overhead |
| 2 | LRU cache for parse_time | schedule.lua | O(1) time parsing |
| 3 | O(1) key lookups | init.lua | Faster lazy loading |
| 4 | Static background lookup | state.lua, core.lua, schedule.lua | Reduced table creation |
| 5 | Cache snacks detection | tui.lua | Avoids repeated pcall |
| 6 | Cache colorscheme list | tui.lua | Faster picker |
| 7 | Cache next_change_at | schedule.lua | Avoids recomputation |
| 8 | Use vim.uv.now() | core.lua | Faster time access |
| 9 | Cached schedule in arm_schedule_timer | core.lua | No re-parsing |
| 10 | Debounced state writes (500ms) | tui.lua | Reduced disk I/O |
| 11 | Static TUI header cache | tui.lua | Faster rendering |
| 12 | Platform detection lookup | system.lua | O(1) platform check |

## 🔄 Remaining Ideas

### Performance Ideas

1. **Incremental schedule validation**: When editing a single entry, only validate that entry instead of the whole schedule.

2. **Precompute boundary table**: For `next_change_at`, could precompute a sorted list of all unique boundaries once instead of iterating all entries every call. Complexity: O(n) → O(log n) for large schedules.

3. **Timer coalescing**: When schedule timer and poll timer would fire close together, coalesce into single timer.

4. **Memory pool for parsed entries**: For very large schedules (>100 entries), use object pooling to reduce GC pressure.

5. **Freeze config after setup**: Make config table read-only after setup() to prevent accidental mutations.

### Features

1. **Fuzzy schedule matching**: Support "sunrise"/"sunset" keywords that resolve to actual times.

2. **Plugin API for custom themes**: Allow users to register custom theme providers.

3. **Profile-guided optimization**: Add instrumentation to measure actual hot paths in production use.
