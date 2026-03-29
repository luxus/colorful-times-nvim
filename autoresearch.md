# Startup Optimization Rules

## Primary Goal
Minimize startup time (time from `require` to ready state) with zero blocking operations.

## Constraints
1. **No blocking I/O** - all file operations must be async
2. **Defer non-critical work** - anything not needed immediately goes to vim.schedule or later
3. **Lazy loading** - delay loading heavy modules until actually needed
4. **Measure**: `require('colorful-times').setup()` total time

## Benchmark
- Measure: time from `require('colorful-times')` through `setup()` completion
- Tool: Neovim `--startuptime` equivalent via Lua
- Runs: 10 iterations for statistical significance

## Optimization Targets
1. State loading (currently sync file I/O)
2. Command registration (defers core loading but still eager)
3. Autocmd registration (could be deferred until enable())
4. Validation (could be async/deferred)
5. First colorscheme application (already async, but triggers early)
