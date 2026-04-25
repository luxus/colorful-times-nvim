# Autoresearch: Match a Minimal Colorscheme Switcher

## Objective

Optimize Colorful Times so its comparable startup and switching costs approach a minimal Neovim colorscheme switcher implemented in under 50 lines of Lua (`bench/minimal-switcher.lua`). The benchmark compares the public user-facing path (`require("colorful-times").setup(opts)`) with the reference switcher across representative configurations, rather than optimizing a single artificial case.

The goal is not to remove Colorful Times features or special-case the benchmark. The reference switcher exists only as a speed target for the simplest shared behavior: accept a default colorscheme/background, optionally choose an active schedule entry, and apply the colorscheme.

## Metrics

- **Primary**: `apply_delta_us` (µs, lower is better) — median Colorful Times apply/switch time minus median minimal-switcher apply/switch time, averaged across benchmark scenarios. This is the active second segment after startup/setup reached parity with the minimal switcher.
- **Secondary**:
  - `delta_us`, `ct_startup_us`, `minimal_startup_us`, `startup_ratio_x` — setup/startup parity guardrails.
  - `ct_resolve_us`, `minimal_resolve_us`, `resolve_delta_us` — schedule/theme resolution cost per call.
  - `ct_apply_us`, `minimal_apply_us` — absolute full apply costs.
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

The startup benchmark measures `require("colorful-times").setup(opts)` and `require("bench.minimal-switcher").setup(opts)` from cleared Lua module caches. The active apply benchmark measures full apply/switch calls after setup, with `vim.schedule(fn)` executing `fn()` immediately so both implementations include background assignment and `:colorscheme`. Both benchmarks average three scenarios:

1. Enabled plugin with no schedule and a dark default background.
2. Enabled plugin with two day/night schedule entries.
3. Disabled plugin with one schedule entry and a light default background.

The benchmark intentionally avoids persistence, external system-appearance detection, and user-local state by setting `persist = false` and isolating XDG directories. This keeps the workload deterministic and focused on startup/setup overhead.

The apply benchmark temporarily makes `vim.schedule(fn)` execute `fn()` immediately so the measured call includes the real background assignment and `:colorscheme` command. Startup/setup delta remains a guardrail: do not regress it catastrophically while improving apply time.

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
- Kept: lazy-loading `schedule.lua` and requiring it only for validation or runtime schedule resolution reduced `delta_us` to `-12.027344`, making setup roughly equal to the minimal switcher in this benchmark.
- Kept: caching the lazy schedule module once per validation loop reduced `delta_us` to `-22.083659`; this is likely close to benchmark noise but keeps the validation code simple.
- Kept: a lightweight core-local setup validator avoids loading `schedule.lua` during startup while preserving synchronous validation errors. This reduced `delta_us` to `-75.263672` and `startup_ratio_x` to `0.834160`. Keep its rules aligned with `schedule.validate_entry()`.
- Discarded: rewriting `schedule.validate_entry()` to store parsed start/stop locals regressed to `delta_us=-3.222005`; parse-time caching already makes repeated calls cheap.
- Discarded: manual field-by-field default merging regressed to `delta_us=25.916341`; keep `vim.tbl_deep_extend()` for default config.
- Discarded: lazy augroup creation in setup regressed to `delta_us=228.875`; keep top-level `nvim_create_augroup()` plus setup-time `nvim_clear_autocmds()`.
- Discarded: localizing `vim.api` regressed to `delta_us=6.930664`; global lookup overhead is not material here.
- Discarded: localizing `nvim_create_user_command` improved `command_us` slightly but worsened primary `delta_us` to `-60.694336`; command registration is not part of the current primary target.
- Segment change: startup/setup parity is achieved (`delta_us=-75.263672`, `startup_ratio_x=0.834160`). The next segment optimizes `apply_delta_us` to keep actual switch/apply cost near the minimal reference as well.
- Existing code already uses lazy loading through `lua/colorful-times/init.lua` and defers heavy setup work through `vim.defer_fn(0)`. Previous startup-focused work found that shallow config copying, `vim.validate()` wrappers, and function-level lazy loading were slower or riskier than current code.
