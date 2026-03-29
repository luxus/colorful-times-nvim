# Startup Optimization Rules

## Status: ✅ COMPLETE

**Final Result**: ~41% improvement (6.88ms → ~4.1ms)
**Approach**: `vim.defer_fn(0)` for zero-blocking startup

## What Was Optimized

All blocking I/O and heavy work moved to deferred execution:
- `state.load()` - file I/O deferred
- Autocmd registration - deferred
- First colorscheme application - deferred  
- Timer creation - deferred

## What's Left (Practical Limit Reached)

The remaining ~4.1ms is:
- `require_ms` (~2.3ms): Loading init.lua → core.lua + submodules (via metatable)
- `setup_ms` (~1.8ms): Validation + `vim.deepcopy` + `defer_fn` setup

Cannot optimize further without:
1. Removing validation (risk: silent failures)
2. Removing `vim.deepcopy` (risk: config mutation bugs)
3. Removing features (schedule validation needs schedule module)

## Experiments Attempted (Regressions)

| Experiment | Result | Lesson |
|------------|--------|--------|
| Split validation (fast/deferred) | +22% slower | Small schedules already fast |
| Lazy submodule loading with getters | +23% slower | Getter overhead > benefit |
| Shallow copy config merging | +27% slower | `vim.deepcopy` is C-optimized |
| Closure-based lazy loading | +22% slower | Metatable `__index` is optimal |
| `vim.validate()` with `pcall` | +4% slower | pcall overhead cancels benefit |
| Function-level lazy loading | +24% slower | Schedule still needed for validation |

## Conclusion

**4.1ms is the practical limit** for this architecture with current features. The plugin now has:
- Zero-blocking startup (all I/O deferred)
- 41% faster time-to-ready
- All tests passing
