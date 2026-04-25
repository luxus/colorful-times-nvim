# Autoresearch: Match a Minimal Colorscheme Switcher

## Objective

Optimize Colorful Times so its comparable startup and switching costs approach a minimal Neovim colorscheme switcher implemented in under 50 lines of Lua (`bench/minimal-switcher.lua`). The benchmark compares the public user-facing path (`require("colorful-times").setup(opts)`) with the reference switcher across representative configurations, rather than optimizing a single artificial case.

The goal is not to remove Colorful Times features or special-case the benchmark. The reference switcher exists only as a speed target for the simplest shared behavior: accept a default colorscheme/background, optionally choose an active schedule entry, and apply the colorscheme.

## Metrics

- **Primary**: `delta_us` (µs, lower is better) — median Colorful Times startup/setup time minus median minimal-switcher startup/setup time, averaged across benchmark scenarios.
- **Secondary**:
  - `ct_startup_us`, `minimal_startup_us`, `startup_ratio_x` — absolute setup costs and ratio.
  - `ct_resolve_us`, `minimal_resolve_us`, `resolve_delta_us` — schedule/theme resolution cost per call.
  - `ct_apply_us`, `minimal_apply_us`, `apply_delta_us` — full apply cost per call with synchronous scheduling in the benchmark harness.
  - `command_us` — cost to source `plugin/colorful-times.lua` and register user commands.

## How to Run

```bash
./autoresearch.sh
```

The script runs headless Neovim with isolated XDG directories and prints `METRIC name=value` lines. Defaults are tuned to keep iterations fast while still using medians:

- `CT_BENCH_SAMPLES=31`
- `CT_BENCH_WARMUP=3`
- `CT_BENCH_APPLY_ITERS=20`
- `CT_BENCH_RESOLVE_ITERS=20000`

Correctness checks run automatically through `autoresearch.checks.sh` after passing benchmark runs:

```bash
nvim --headless \
  -u tests/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"
```

## Benchmark Design

The primary benchmark measures `require("colorful-times").setup(opts)` and `require("bench.minimal-switcher").setup(opts)` from cleared Lua module caches. It averages three scenarios:

1. Enabled plugin with no schedule and a dark default background.
2. Enabled plugin with two day/night schedule entries.
3. Disabled plugin with one schedule entry and a light default background.

The benchmark intentionally avoids persistence, external system-appearance detection, and user-local state by setting `persist = false` and isolating XDG directories. This keeps the workload deterministic and focused on startup/setup overhead.

The apply benchmark temporarily makes `vim.schedule(fn)` execute `fn()` immediately so the measured call includes the real background assignment and `:colorscheme` command. This is a secondary metric only; the primary metric remains startup/setup delta.

## Files in Scope

- `lua/colorful-times/init.lua` — public module, lazy loading, default config.
- `lua/colorful-times/core.lua` — setup, validation, runtime scheduling, theme resolution, apply path.
- `lua/colorful-times/schedule.lua` — schedule parsing, validation, active-entry lookup, next-change lookup.
- `lua/colorful-times/state.lua` — persistence loading/merging/saving; changes allowed only if tests continue to cover persisted behavior.
- `lua/colorful-times/system.lua` — system background detection; avoid touching unless it directly affects setup overhead without changing behavior.
- `plugin/colorful-times.lua` — command registration cost.
- `bench/minimal-switcher.lua` — reference implementation; keep under 50 lines and do not slow it down to make Colorful Times look better.
- `bench/autoresearch_minimal_compare.lua` — benchmark harness; changes must improve measurement quality, not favor Colorful Times.
- `tests/` — add or update tests when behavior changes.
- `doc/colorful-times.txt` and `README.md` — update only if public behavior changes.

## Off Limits

- Do not remove documented features to win the benchmark.
- Do not special-case benchmark inputs, environment variables, paths, or module names in production code.
- Do not weaken tests, skip correctness checks, or alter the minimal reference to make Colorful Times look faster.
- Do not introduce new runtime dependencies.
- Do not optimize solely for empty schedules; the two-entry and disabled scenarios must stay representative.

## Constraints

- Neovim >= 0.12 behavior must remain supported.
- All tests must pass after kept experiments.
- Public API behavior and command names must remain compatible unless the user explicitly approves a breaking change.
- Timer and async rules from `AGENTS.md` apply: use `vim.schedule()` for main-thread Vim API work from async callbacks, close timers safely, and avoid overlapping async work.
- Favor simple, maintainable changes. A small speedup is not worth fragile code.

## What's Been Tried

- Baseline: `delta_us=460.916992`, `ct_startup_us=931.777995`, `minimal_startup_us=470.861003`, `startup_ratio_x=1.978881`.
- Kept: lazy-loading `state.lua` and `system.lua` from `core.lua` reduced `delta_us` to `41.138672` and `startup_ratio_x` to `1.087762`. This worked because the primary setup path uses `persist=false` and non-system backgrounds, so persistence and system detection are not needed at require time.
- Existing code already uses lazy loading through `lua/colorful-times/init.lua` and defers heavy setup work through `vim.defer_fn(0)`. Previous startup-focused work found that lazy submodule getters, shallow config copying, `vim.validate()` wrappers, and function-level lazy loading were slower or riskier than current code.
