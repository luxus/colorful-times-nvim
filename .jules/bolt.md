# Performance Optimization: Table Allocation for Static Keys

## Optimization:
- Extracted static keys for themes and state properties into top-level local constants.
- Impacted files: `lua/colorful-times/state.lua`, `lua/colorful-times/core.lua`.

## Rationale:
In Lua, creating a table `{ "key1", "key2" }` inside a function results in a new heap allocation every time that function is called. In performance-critical paths like state validation or merging (which happen on startup and during user interaction), these short-lived allocations increase Garbage Collection (GC) pressure.

By moving these to local constants at the module level:
1. **Zero Runtime Allocation**: The tables are created once when the module is loaded.
2. **Reduced GC Cycles**: Eliminates "garbage" that needs to be collected, leading to smoother performance and less CPU time spent in the collector.
3. **Micro-optimization**: Although each individual allocation is small, avoiding them is a standard "expert-level" practice in Lua development for Neovim plugins to ensure minimal overhead.

## Verification:
Due to environment restrictions (no nvim/luajit/plenary available), direct benchmarking was not possible. However, this change is a well-documented Lua performance best practice and consistent with other optimizations already present in the codebase.
