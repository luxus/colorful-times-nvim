# Future Optimization Ideas

## ✅ Completed (13 optimizations)

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
| 13 | Async startup via vim.defer_fn | core.lua | **41% faster startup (6.88ms → 4.1ms)** |

## 🚫 Tried & Reverted (6 experiments - all regressed)

| Idea | Result | Lesson |
|------|--------|--------|
| Split validation (fast/deferred) | +22% slower | Small schedules already fast |
| Lazy submodule loading with getters | +23% slower | Getter overhead > benefit |
| Shallow copy config merging | +27% slower | `vim.deepcopy` is C-optimized |
| Closure-based lazy loading | +22% slower | Metatable `__index` is optimal |
| vim.validate() with pcall | +4% slower | pcall overhead cancelled benefit |
| Function-level lazy loading | +24% slower | Schedule still needed for validation |

## 🚫 Not Pursued (Insufficient benefit for typical use)

| Idea | Why Not Pursued |
|------|-----------------|
| Memory pool for parsed entries | Only relevant for >100 entry schedules (edge case) |
| Timer coalescing | Complexity not worth it for typical 5s poll intervals |

## 🔄 Active: Runtime Performance

### Current Target: `next_change_at` Optimization

**Problem**: `next_change_at()` is O(n) - iterates all entries and boundaries every call
**Idea**: Precompute sorted unique boundaries once → O(log n) via binary search
**Benefit**: Significant for large schedules (>20 entries)
**Status**: NOT YET TRIED

Implementation approach:
1. Add `boundaries` field to parsed schedule (sorted array of unique boundaries)
2. Add `next_boundary_idx` field (circular index for current position)
3. Modify `next_change_at` to use binary search or cached index

---

## 📋 Backlog (Future Ideas)

### Features (Not Performance)

1. **Fuzzy schedule matching**: Support "sunrise"/"sunset" keywords that resolve to actual times
2. **Plugin API for custom themes**: Allow users to register custom theme providers
3. **Incremental schedule validation in TUI**: When editing a single entry, only validate that entry

### Edge Cases

4. **Large schedule optimization**: For schedules with >50 entries, consider additional optimizations
