# Autoresearch: Match a Minimal Colorscheme Switcher

## Objective

Optimize Colorful Times so its comparable startup and switching costs approach a minimal Neovim colorscheme switcher implemented in under 50 lines of Lua (`bench/minimal-switcher.lua`). The benchmark compares the public user-facing path (`require("colorful-times").setup(opts)`) with the reference switcher across representative configurations, rather than optimizing a single artificial case.

The goal is not to remove Colorful Times features or special-case the benchmark. The reference switcher exists only as a speed target for the simplest shared behavior: accept a default colorscheme/background, optionally choose an active schedule entry, and apply the colorscheme.

## Metrics

- **Primary**: `first_apply_delta_us` (µs, lower is better) — median paired Colorful Times cold first-apply time after setup minus minimal-switcher cold first-apply time across the broadened four-scenario workload.
- **Secondary**:
  - `delta_us` — setup/startup parity guardrail.
  - `apply_delta_us` — steady-state apply/switch parity guardrail.
  - `ct_startup_us`, `minimal_startup_us`, `startup_ratio_x` — absolute setup/startup costs and ratio.
  - `ct_resolve_us`, `minimal_resolve_us`, `resolve_delta_us` — schedule/theme resolution cost per call.
  - `ct_apply_us`, `minimal_apply_us` — absolute full apply costs.
  - `command_us` — plugin command registration cost guardrail.
- **Diagnostics**:
  - `delta_p25_us`, `delta_p75_us`, `delta_iqr_us` — paired startup delta spread for judging noise.
  - `apply_delta_p25_us`, `apply_delta_p75_us`, `apply_delta_iqr_us` — paired steady-state apply delta spread for judging noise.
  - `first_apply_delta_us`, `first_apply_delta_p25_us`, `first_apply_delta_p75_us`, `first_apply_delta_iqr_us` — cold first-apply delta/spread after setup, before schedule preprocessing is amortized.
  - `ct_first_apply_us`, `minimal_first_apply_us` — absolute cold first-apply costs.
  - `first_apply_delta_empty_us`, `first_apply_delta_two_entry_us`, `first_apply_delta_disabled_us`, `first_apply_delta_hourly_us` — per-scenario cold first-apply deltas.
  - `command_p25_us`, `command_p75_us`, `command_iqr_us` — command registration spread for judging noise.
  - `delta_empty_us`, `delta_two_entry_us`, `delta_disabled_us`, `delta_hourly_us` — per-scenario startup deltas.
  - `apply_delta_empty_us`, `apply_delta_two_entry_us`, `apply_delta_disabled_us`, `apply_delta_hourly_us` — per-scenario apply deltas.

## How to Run

```bash
./autoresearch.sh
```

The script runs headless Neovim with isolated XDG directories and prints `METRIC name=value` lines. Defaults are tuned to keep iterations fast while still using medians:

- `CT_BENCH_SAMPLES=31`
- `CT_BENCH_WARMUP=3`
- `CT_BENCH_STARTUP_ITERS=9`
- `CT_BENCH_APPLY_ITERS=100`
- `CT_BENCH_COMMAND_ITERS=10`
- `CT_BENCH_RESOLVE_ITERS=20000`

Correctness checks run automatically through `autoresearch.checks.sh` after passing benchmark runs:

```bash
nvim --headless \
  -u tests/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"
```

## Benchmark Design

The startup benchmark measures `require("colorful-times").setup(opts)` and `require("bench.minimal-switcher").setup(opts)` from cleared Lua module caches. The active apply benchmark measures full apply/switch calls after setup, with `vim.schedule(fn)` executing `fn()` immediately so both implementations include background assignment and `:colorscheme`. Both benchmarks average four scenarios:

1. Enabled plugin with no schedule and a dark default background.
2. Enabled plugin with two day/night schedule entries.
3. Disabled plugin with one schedule entry and a light default background.
4. Enabled plugin with a representative 24-entry hourly schedule.

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
- Apply baseline after segment reset: `apply_delta_us=17.763200`.
- Kept: scalar theme resolution for hot paths avoids allocating a context table in `apply_colorscheme()` and `resolve_theme()`. This reduced `apply_delta_us` to `4.365283` while keeping startup faster than the minimal reference.
- Superseded: `apply_colorscheme()` applying synchronously outside fast events looked faster under the noisy 20-iteration apply benchmark, but the stable 100-iteration benchmark showed unconditional scheduling was better and safer.
- Kept: reverting to unconditional `vim.schedule()` for apply under the stable benchmark reduced `apply_delta_us` to `-16.010697` and preserved prior async timing semantics.
- Discarded: removing the small apply scheduling helper and inlining `vim.schedule()` regressed to `apply_delta_us=15.905830`; keep the helper.
- Discarded: localizing `vim.in_fast_event` regressed to `apply_delta_us=21.918734`.
- Discarded: removing the `vim.in_fast_event` existence guard regressed to `apply_delta_us=7.679850`; this path was later superseded by unconditional scheduling.
- Discarded: inlining `apply_when_safe()` in the common non-system branch regressed to `apply_delta_us=13.908333`; keep the helper.
- Discarded: skipping schedule lookup for empty schedules improved versus segment baseline but regressed versus current best (`apply_delta_us=1.833317` vs `-11.345133`). Revisit only if the benchmark separates cold first-apply from steady-state apply.
- Benchmark stability update: apply iterations increased from 20 to 100 and samples reduced from 31 to 21. Stable segment baseline was `apply_delta_us=18.804030`; keep results in this segment separate from earlier noisy apply runs.
- No-code confirmation of the stable apply best reran at `apply_delta_us=-1.697780`, worse than the best `-16.010697` but still better than baseline. Treat sub-10µs apply changes cautiously.
- Benchmark stability update: `apply_delta_us` now uses the median of paired Colorful Times/minimal apply deltas rather than subtracting independent medians. Paired baseline is `apply_delta_us=-0.055140`, effectively parity with the minimal switcher.
- Discarded: retrying the empty-schedule fast path under paired apply still regressed to `apply_delta_us=3.585003`.
- Discarded: reverting hot apply/resolve calls to table-based context resolution regressed to `apply_delta_us=8.637777`; scalar resolution remains useful.
- Benchmark broadened: added a representative 24-entry hourly schedule scenario so startup/apply parity is not overfit to tiny schedules. Four-scenario baseline: `apply_delta_us=3.075315`, `delta_us=-91.343506`.
- Discarded: inlining active-entry range checks and using a numeric loop in `schedule.get_active_entry()` regressed to `apply_delta_us=9.735313`; keep the helper-based implementation.
- Discarded: precomputing parsed schedules during `setup()` for `persist=false` configs regressed to `apply_delta_us=10.080420` and broke startup parity (`delta_us=52.405762`). Keep lazy schedule preprocessing.
- Discarded: replacing `table.insert()` with direct array appends in `schedule.preprocess()` regressed to `apply_delta_us=5.346250`; keep `table.insert()`.
- Discarded: caching active schedule entries for non-overlapping schedules regressed to `apply_delta_us=8.048337`; cache checks/preprocess overhead outweighed lookup savings.
- Segment change: setup/apply parity is achieved under the broadened paired benchmark. Current segment targets `command_us` as remaining startup-adjacent overhead, while keeping `apply_delta_us` and `delta_us` as guardrails.
- Command baseline: `command_us=80.750000`.
- Kept: localizing `vim.api.nvim_create_user_command` in `plugin/colorful-times.lua` reduced `command_us` to `57.041992` without changing command behavior.
- Benchmark stability update: `command_us` now averages 10 command registration/delete cycles per sample. Stable baseline after localizing `nvim_create_user_command`: `command_us=56.833203`.
- Discarded: generating common command callbacks through a helper regressed to `command_us=61.291992` and again to `60.354297` under the stable command benchmark; keep explicit callbacks.
- Discarded: moving `ColorfulTimesStatus` formatting into a lazy module regressed to `command_us=75.583008`; status callback size is not the bottleneck.
- Discarded: localizing `require` for command callbacks regressed to `command_us=63.958984`; do not localize globals used only inside callbacks.
- Discarded: removing explicit `require("colorful-times.core")` from callbacks regressed to `command_us=58.816406`; keep explicit core requires for clarity.
- Discarded: reusing a single mutable command opts table regressed to `command_us=59.437500`; keep separate literal opts tables.
- No-code confirmation of stable command best reran worse (`command_us=58.591699` vs best `56.833203`), so sub-2µs command changes should be treated as noise. Command path appears exhausted.
- Segment change: returned to `delta_us` on the broadened four-scenario workload and keep `apply_delta_us`/`command_us` as guardrails. Baseline: `delta_us=-84.239502`.
- Superseded: `vim.deepcopy(..., true)` looked noisy across earlier paired/independent benchmark variants. Under the stable paired startup benchmark with five startup cycles per sample, noref deepcopy improved from `delta_us=-76.885498` to `-83.797803` and confirmed at `-84.797754`. Keep noref deepcopy for setup-time config copies.
- Earlier no-code confirmation of the noref deepcopy state reran much worse (`delta_us=56.718994`) under the independent-median startup metric, showing that older metric was too noisy.
- Benchmark stability update: `delta_us` now uses the median of paired Colorful Times/minimal startup deltas. Paired startup baseline after noref deepcopy: `delta_us=-76.968262`.
- Benchmark stability update: `CT_BENCH_STARTUP_ITERS=5` averages five startup cycles per sample before paired `delta_us`. Stable paired startup baseline: `delta_us=-76.885498`.
- Kept: noref deepcopy for setup-time config copies under the stable paired startup benchmark; best confirmed value so far is `delta_us=-84.797754`.
- Kept but noisy: using noref only for the user `opts` copy and regular deepcopy for `_base_config` produced `delta_us=-90.752197`, but a no-code confirmation reran near baseline (`-77.562451`). Reverting opts noref to regular also measured near baseline (`-77.650049`) and was discarded, so current code keeps opts-only noref. The opposite split (`opts` regular, `_base_config` noref) measured `-90.576904` but worsened `command_us` to `84.087402` and was discarded. Do not pursue more noref split experiments.
- Discarded: moving status table construction into a lazy status module measured `delta_us=-88.347803`, not enough to justify added private helper surface and module split.
- Discarded: manual byte parsing for core-local setup time validation measured `delta_us=-83.650049` and was much less maintainable; keep string pattern validation.
- Checks-failed probe: removing focus autocmds entirely measured `delta_us=-108.054004`, showing an upper-bound cost but failing correctness.
- Discarded: conditional focus autocmd registration with updated tests measured `delta_us=-60.837695`; schedule scanning/sync logic outweighed avoided autocmd API calls. Keep unconditional focus autocmds.
- Segment change pending: startup delta is again at parity under the stable paired benchmark. Next segment targets `apply_delta_us` to explore the schedule runtime split idea while keeping `delta_us` and `command_us` as guardrails.
- Benchmark fairness update: paired startup/apply samples now alternate Colorful Times/minimal measurement order to reduce ordering bias. Alternating-order apply baseline: `apply_delta_us=0.352397` with `delta_us=-84.464648`.
- No-code confirmation of alternating-order apply baseline reran at `apply_delta_us=3.508440`; remaining apply differences are small/noisy, so avoid large schedule-runtime refactors unless they show repeated >5µs wins or simplify code.
- Checks-failed/discarded: moving the `open()` wrapper from `core.lua` to `init.lua` worsened apply and broke lazy-loading expectations; keep `open()` in core.
- Discarded: core-only `schedule_runtime.lua` split measured `apply_delta_us=0.152603`, only 0.20µs better than baseline, while duplicating schedule logic and worsening `command_us`; not keepable.
- Discarded: caching core-local setup time validation results regressed to `delta_us=-80.833252`; keep simple uncached validation.
- Discarded: combining FocusLost/FocusGained into one autocmd callback regressed to `delta_us=-75.270752`; keep separate autocmd registrations.
- Discarded: adding an explicit `M.setup` wrapper in `init.lua` regressed to `delta_us=-98.062500`; metatable lazy loading remains better.
- Discarded: unrolling default theme validation and removing `THEME_KEYS` regressed to `delta_us=-75.187500`; keep the compact loop.
- Discarded: replacing `_lazy_keys` table with inline string comparisons in `init.lua` regressed to `delta_us=-96.072998`; keep the lookup table.
- Discarded: using `package.loaded["colorful-times"] or require(...)` in `core.lua` regressed to `delta_us=-76.604248`; keep direct `require("colorful-times")`.
- Discarded: skipping the first setup-time `nvim_clear_autocmds()` regressed to `delta_us=-75.677734`; keep unconditional autocmd clear in setup.
- Discarded: skipping the deferred setup callback for `persist=false` and `enabled=false` regressed to `delta_us=-94.541260`; keep the unconditional defer path.
- Discarded: removing explicit nil defaults from the public config table regressed to `delta_us=-94.979492`; keep them for readability.
- Existing code already uses lazy loading through `lua/colorful-times/init.lua` and defers heavy setup work through `vim.defer_fn(0)`. Previous startup-focused work found that shallow config copying, `vim.validate()` wrappers, and function-level lazy loading were slower or riskier than current code.
- Discarded: localizing `cfg.default` inside `resolve_theme_parts()` regressed to `apply_delta_us=2.395522`; keep current direct lookups.
- Segment change: apply is at parity/noise under alternating paired measurement. Switched primary back to stable paired `delta_us` to evaluate startup structure, keeping `apply_delta_us` and `command_us` as guardrails. Baseline `delta_us=-107.785400`.
- Discarded: grouping `opts.default` validation around one local default table regressed to `delta_us=-77.902002`; keep existing direct checks.
- Discarded: lazy access to `vim.uv` in timer-start paths regressed to `delta_us=-93.674902`; keep top-level `local uv = vim.uv`.
- Reverted: replacing setup validation `ipairs(opts.schedule)` with a numeric loop was weak/noisy under 31-sample runs; under the steadier 31×9 benchmark, reverting it together with the hoisted defer callback improved `delta_us` from `-62.120334` to `-88.671170`. Keep idiomatic `ipairs` validation.
- Discarded: binding `opts.schedule` to a local before the validation loop regressed to `delta_us=-83.341748`; keep the numeric loop exactly as committed.
- Benchmark stability change: increased default samples from 21 to 31 to reduce noise before more sub-10µs startup experiments. New 31-sample baseline: `delta_us=-92.008154`, `apply_delta_us=1.292185`, `command_us=56.337500`.
- Benchmark stability change: increased startup iterations per sample from 5 to 9 to reduce startup noise. New 31×9 startup baseline: `delta_us=-62.120334`, `apply_delta_us=2.561667`, `command_us=57.558398`.
- Kept/confirmed: under the 31×9 benchmark, reverting the two weak kept setup changes (numeric validation loop and hoisted defer callback) improved `delta_us` to `-88.671170`; no-code confirmation improved further to `-95.202393` with `apply_delta_us=-1.840728` and `command_us=56.762695`. Do not revisit these changes.
- Discarded: splitting rare enable/disable/toggle/reload actions into `actions.lua` wrappers regressed to `delta_us=-63.777669`, worsened `apply_delta_us=7.008228`, and added private-hook complexity. Do not pursue this broader action split shape.
- Discarded: localizing core autocmd API functions regressed to `delta_us=-90.428906`; keep direct `vim.api` calls.
- Discarded: hoisting focus autocmd callbacks/options regressed to `delta_us=-84.466602`; keep inline setup callbacks/options.
- Reverted: hoisting the deferred setup callback was weak/noisy under 31-sample runs; under the steadier 31×9 benchmark, reverting it together with the numeric validation loop improved `delta_us` from `-62.120334` to `-88.671170`. Keep the inline deferred callback.
- Discarded: explicit schema-field default merge regressed to `delta_us=-63.506055`; keep `vim.tbl_deep_extend("force", ...)`.
- Discarded: localizing `vim.deepcopy` and `vim.tbl_deep_extend` measured only a small/noisy delta gain (`-94.345752`) with worse `command_us=64.666504`; keep direct calls.
- Discarded: inline background validation comparisons regressed to `delta_us=-55.837598`; keep `VALID_BACKGROUNDS[...]` lookups.
- Discarded: replacing the small `_timers` table with separate `_schedule_timer`/`_poll_timer` locals measured `delta_us=-86.059082`, worse than current confirmed `-95.202393`, and worsened guardrails; keep `_timers` table.
- Benchmark diagnostics kept: paired-delta p25/p75/IQR metrics now report startup/apply noise. First successful run measured `delta_iqr_us=37.452664` and `apply_delta_iqr_us=19.544790`; no-code confirmation measured `delta_us=-93.819417`, `delta_iqr_us=47.909559`, and `apply_delta_iqr_us=11.943855`. Sub-10µs single-run changes are below noise. First attempt crashed because `collect_apply_pair()` still returned only three values; fixed in the kept retry.
- Fresh idea review after diagnostics found no promising untried non-overfit code paths; remaining ideas are micro-optimizations below the measured IQR or repeats of discarded structural splits.
- Benchmark diagnostics kept: per-scenario startup delta metrics now report scenario parity without changing the aggregate primary metric. First run: `delta_empty_us=-94.111003`, `delta_two_entry_us=-80.388780`, `delta_disabled_us=-88.162218`, `delta_hourly_us=-42.069878`; hourly is weakest but still faster than the minimal reference.
- Benchmark diagnostics kept/confirmed: per-scenario apply delta metrics now complement startup scenario metrics without changing the primary aggregate metric. First run: `apply_delta_empty_us=3.605000`, `apply_delta_two_entry_us=7.482490`, `apply_delta_disabled_us=-1.272090`, `apply_delta_hourly_us=4.993330`; confirmation: `apply_delta_empty_us=-0.225830`, `apply_delta_two_entry_us=6.200420`, `apply_delta_disabled_us=-3.193750`, `apply_delta_hourly_us=6.732080`. All are within measured apply IQR, so apply remains parity/noise-limited. Confirmation also measured startup scenario deltas all faster than minimal (`delta_empty_us=-90.856337`, `delta_two_entry_us=-83.930664`, `delta_disabled_us=-77.268446`, `delta_hourly_us=-70.296224`).
- Benchmark diagnostics kept: per-scenario diagnostics now reuse existing paired startup/apply samples instead of running separate scenario passes, preserving metric names while reducing benchmark runtime from ~34s back to ~17s. First refactor run: `delta_us=-83.709554`, `delta_iqr_us=39.076362`, `apply_delta_iqr_us=14.074797`. No-code confirmation reran noisier at `delta_us=-67.328722`, but all scenario startup deltas remained faster than minimal and apply scenario deltas remained within IQR; keep the refactor for runtime/diagnostic quality.
- Benchmark diagnostics kept/confirmed: added `command_p25_us`, `command_p75_us`, and `command_iqr_us` so future command registration tweaks are judged against measured command noise. First run measured `command_us=57.325098`, `command_iqr_us=4.775098`; confirmation measured `command_us=60.004199`, `command_iqr_us=6.620801`, confirming previous sub-2µs command tweaks were below noise.
- Benchmark integrity check kept: `autoresearch.checks.sh` now verifies `bench/minimal-switcher.lua` stays under 50 lines so the reference target cannot be weakened accidentally. Checks passed; first run measured `delta_us=-80.368083` with metric movement inside measured noise.
- Benchmark integrity check kept/confirmed: `autoresearch.checks.sh` now also verifies `bench/minimal-switcher.lua` stays independent of `colorful-times` modules/references. First run measured `delta_us=-82.832194`; no-code confirmation measured `delta_us=-89.192139`. All startup scenario deltas remained negative.
- Benchmark diagnostics kept/confirmed: added cold first-apply delta/spread metrics so the 100-iteration steady-state apply average does not hide first-switch schedule preprocessing costs. First run measured `first_apply_delta_us=179.000244`, `first_apply_delta_iqr_us=66.843750`, `ct_first_apply_us=1023.125488`, `minimal_first_apply_us=845.479248`; confirmation measured `first_apply_delta_us=197.552246`, `first_apply_delta_iqr_us=156.510498`, `ct_first_apply_us=1037.521240`, `minimal_first_apply_us=847.947998`. Steady-state `apply_delta_us` remained inside noise. Keep first-apply diagnostic-only unless the user explicitly changes target/workload.
- Benchmark diagnostics kept/confirmed: per-scenario cold first-apply deltas show where the first-switch gap comes from. First run: `first_apply_delta_empty_us=134.333008`, `first_apply_delta_two_entry_us=142.791992`, `first_apply_delta_disabled_us=17.375977`, `first_apply_delta_hourly_us=315.208008`; confirmation: `first_apply_delta_empty_us=133.791016`, `first_apply_delta_two_entry_us=134.166992`, `first_apply_delta_disabled_us=4.458984`, `first_apply_delta_hourly_us=277.666992`. The gap is largest for hourly schedules but also visible in enabled non-hourly scenarios.
- Segment change: cold first-apply is a real switch/apply behavior not covered by the 100-iteration steady-state average. Primary is now `first_apply_delta_us`, with `delta_us`, steady-state `apply_delta_us`, and `command_us` as guardrails. Baseline: `first_apply_delta_us=149.531006`, `first_apply_delta_iqr_us=115.156494`, `delta_us=-73.446777`, `apply_delta_us=5.917708`, `command_us=56.779297`. Avoid moving work into setup unless startup guardrail remains clearly faster than minimal.
- Kept/confirmed: splitting runtime schedule parse/lookup helpers into `schedule_runtime.lua` initially improved `first_apply_delta_us` from `149.531006` to `128.604492`; first no-code confirmation was noisy (`151.708252`), but reverting the split worsened primary to `181.333008`, and a reconfirmation returned to `128.197754`. Guardrails were clean (`delta_us=-89.881972`, `apply_delta_us=5.066458`, `command_us=56.024902`). Keep the split under the first-apply segment despite added internal module and partial validation duplication; avoid further broad schedule rewrites unless they reduce duplication without hurting first apply.
- Kept/confirmed: exposed `validate_entry` from `schedule_runtime.lua` and re-exported it from `schedule.lua`, removing duplicated validation logic introduced by the runtime split. First run improved `first_apply_delta_us` to `125.260254`; confirmation was noisier but still below baseline at `144.062744`. Startup guardrail stayed clearly negative. Keep because it simplifies the split and centralizes schedule validation behavior.
- Experiment pending: skip schedule runtime loading/preprocessing/timers when enabled config has no schedule entries, preserving default behavior while targeting cold first-apply overhead in the empty-schedule scenario.
