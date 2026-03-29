# Future Optimization Ideas

## Performance Ideas

1. **Batch state writes**: Currently state is saved immediately on every TUI change. Could debounce/batch writes to reduce disk I/O.

2. **Incremental schedule validation**: When editing a single entry, only validate that entry instead of the whole schedule.

3. **Precompute boundary table**: For `next_change_at`, could precompute a sorted list of all boundaries once instead of iterating all entries every call.

4. **Use vim.uv time instead of os.date**: Could use `uv.now()` or `uv.hrtime()` for more efficient time calculations.

5. **Lazy parse schedule entries**: Only parse schedule entries when they're actually needed (time-based lazy parsing).

6. **Timer coalescing**: When multiple timers would fire close together, could coalesce them into a single timer.

7. **Memory pool for parsed entries**: For very large schedules, could use a memory pool to reduce GC pressure.

## Code Quality Ideas

1. **Type-safe config merging**: Use stricter types for config merging to catch errors at edit time.

2. **Async state persistence**: Make state save truly async with proper error handling.

3. **Plugin API for custom themes**: Allow users to register custom theme providers.
