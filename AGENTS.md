# AGENTS.md - Colorful Times

Behavioral guidelines and project context for AI agent sessions. Merge with higher-level instructions as needed.

This repo is a Neovim plugin written in Lua. Neovim requirement: >= 0.12.0. Tests use plenary.nvim + busted.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

---

# Agent Behavioral Contract

These rules override all other instructions when they conflict. They exist to reduce LLM coding drift, over-engineering, and speculative changes.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```text
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

# Agent Execution Protocol

Operational execution rules for this coding agent session. Strength at long-horizon coding needs strict scope control to avoid fast drift.

## 5. Operational, Not Conversational

Work from explicit instructions. If the user's request is vague, stop and clarify. Do not proceed on best-guess intent.

**Pattern:** `read-before-write → evidence-before-action → minimal diff → verify-before-report`

## 6. Read Before Write

Do not infer repository paths, APIs, helpers, or behavior. Confirm facts by:
1. Reading files explicitly (`read`, `rg`, `find`).
2. Following local project docs (`AGENTS.md`, `README.md`, `CONTEXT.md`, `CHANGELOG.md`).
3. Running verification commands before claiming understanding.

## 7. Lock the Scope

- No opportunistic refactors.
- No unrelated cleanup.
- No files outside the target set.
- If the user asks for X, deliver X. Do not also deliver Y because "it might be useful."

## 8. Define Stop Gates

Ambiguity, missing files, conflicting docs, forbidden commands, or unclear scope should produce **BLOCKED**. Stop and ask before proceeding.

Do not proceed with best-guess assumptions. Surface uncertainty explicitly.

## 9. Require Proof, Not Confidence

Confirm work with actual checks before claiming success:
- Run tests (`nvim --headless -u tests/minimal_init.vim …`).
- Check command output.
- Verify file contents match intent.
- Re-read your own edits to ensure correctness.

## 10. Compaction Recovery

For long tasks, recovery state must be inspectable:
- Use `git diff` to show current changes.
- Track modified files explicitly.
- Persist verification state.
- Keep a running result artifact if the task spans multiple turns.

---

# Project Context

## 0. Meta-Protocol Principles

- `Constraint-Driven Evolution`: Add structure when the plugin gains real runtime or user constraints.
- `Single Source of Truth`: Keep durable rules in `AGENTS.md`, open work in GitHub issues, completed delivery in `CHANGELOG.md`, and deeper technical detail in `/docs`.
- `Boundary Clarity`: Separate theme resolution concerns, schedule runtime concerns, TUI concerns, system detection concerns, and state persistence concerns.
- `Progressive Enhancement + Graceful Degradation`: Prefer behavior that upgrades automatically when richer runtime context exists, but always preserves a useful fallback path.
- `Runtime Safety`: Prefer predictable queue/timer behavior over clever behavior that can desynchronize the plugin state.

## 1. Concept

Colorful Times is a Neovim plugin that chooses a colorscheme and background from a user-defined theme schedule, the default theme, optional system background detection, and a session hold. Treat it as a runtime theme resolver with a TUI editor, not just a static colorscheme switcher.

## 2. Identity & Naming Contract

Use the domain vocabulary from `CONTEXT.md` exactly. Key terms:

- `Theme schedule`: A set of time ranges that may choose a colorscheme and requested background for the current wall-clock time.
- `Theme resolution`: The policy that chooses the active colorscheme, requested background, resolved background, and source.
- `Requested background`: The background value (`light`, `dark`, `system`) before system detection is applied.
- `Resolved background`: The concrete `light` or `dark` that Neovim should apply.
- `System background detection`: The platform-specific mechanism that resolves `system` to `light` or `dark`.
- `Session hold`: A runtime-only override that pins the current theme until released or Neovim exits.
- `Schedule runtime`: Internal implementation that parses, validates, preprocesses, and queries the theme schedule. Not a public interface.
- `TUI action policy`: State machine that turns a TUI user action into new TUI state plus effect intents.
- `Effect intent`: Data description of a side effect requested by TUI action policy.
- `Render plan`: Complete data needed to draw the TUI before buffer/window APIs are called.

## 3. Project Topology

- `/plugin/colorful-times.lua`: Plugin entrypoint (commands, autocmds).
- `/lua/colorful-times/init.lua`: Public API module.
- `/lua/colorful-times/core.lua`: Core theme application and state management.
- `/lua/colorful-times/theme_resolution.lua`: Theme resolution policy.
- `/lua/colorful-times/schedule_runtime.lua`: Schedule parsing, validation, and querying.
- `/lua/colorful-times/state*.lua`: State policy, filesystem adapter, and TUI state.
- `/lua/colorful-times/system*.lua` + `/lua/colorful-times/system/`: System background detection backends (darwin, linux, custom, env, process).
- `/lua/colorful-times/tui/`: TUI subsystem — action policy, actions, highlights, keys, layout, preview, render, render plan, selectors, state, view model.
- `/lua/colorful-times/health.lua`: `:checkhealth` integration.
- `/tests/*.lua`: Plenary-busted test suites mirroring the module structure.
- `/doc/colorful-times.txt`: Vim help documentation.
- `/README.md`: User-facing project entry point.
- `/CONTEXT.md`: Domain glossary and relationships.
- `/docs/agents/`: Agent skill configuration.

## 4. Core Entities

- `Theme schedule`: User-defined time-range → colorscheme/background mapping.
- `Default theme`: Fallback colorscheme, background, and optional overrides.
- `Theme resolution`: The combined policy producing active colorscheme + resolved background + source.
- `Detection plan`: Backend-specific description of how to perform system background detection.
- `Persisted state policy`: Decodes, validates, encodes, and merges state bytes without file I/O.
- `State filesystem adapter`: Reads state bytes, writes atomically, backs up corrupt files.

## 5. Architectural Decisions

## 5.1 Module Boundaries

- `theme_resolution.lua` owns the full resolution policy. Callers use it; they do not reimplement fallback rules.
- `schedule_runtime.lua` is internal. Public callers should use `theme_resolution.lua` rather than depending on schedule parsing or cache behavior.
- `system.lua` + `system/*.lua` own all platform detection. Core and TUI consume resolved values; they do not reimplement backend selection.
- `state_policy.lua` owns bytes-to-state rules; `state.lua` (filesystem adapter) owns filesystem effects only.
- TUI domains are split: `action_policy.lua` produces `Effect intent`s; `render_plan.lua` builds data; `render.lua` executes against Neovim APIs.

## 5.2 Async and Timer Rules

- Use `vim.schedule()` for main-thread Vim API work triggered from async callbacks.
- Always close timers properly and check `is_closing()` before closing handles.
- Avoid timer leaks and overlapping async work.
- System background detection is async; the TUI preview must not invoke it. Preview consumes a known `Resolved background`.

## 6. Engineering Conventions

## 6.1 Validation Hotspots

- Treat schedule parsing, theme resolution edge cases, and state persistence as regression-prone areas.
- Validate them after changing resolution logic, schedule format handling, or state shape.
- Detection backend fallback order and executable checks must be tested per platform.

## 6.2 File and Naming Style

- Keep comments and user-facing docs in English.
- Each Lua module should start with a short header comment explaining its boundary.
- Test files mirror module names: `schedule_runtime.lua` → `schedule_spec.lua`, `core.lua` → `core_spec.lua`.
- Prefer targeted edits. Move reusable logic into its own domain module only when a subsystem is large enough to earn extraction.
- Keep `init.lua` as the public API surface. Internal logic lives in named modules.

## 6.3 Current Domain Ownership Snapshot

- Theme resolution and application: `core.lua`, `theme_resolution.lua`
- Schedule runtime: `schedule_runtime.lua`
- State persistence: `state_policy.lua`, `state.lua`
- System detection: `system.lua`, `system/*.lua`
- TUI: `tui/*.lua`
- Health checks: `health.lua`
- Public API: `init.lua`

## 7. Operational Conventions

- When user-facing behavior changes, sync `README.md` and `doc/colorful-times.txt` in the same pass.
- When durable runtime constraints or repeat bug patterns emerge, record them here instead of burying them in changelog prose.
- Keep `CHANGELOG.md` accurate. Add entries for user-facing changes.

## 8. Pre-Task Preparation Protocol

- Read `README.md` for current user-facing behavior.
- Read `CONTEXT.md` before changing domain terminology or architectural boundaries.
- Inspect the relevant module and its mirrored test file before editing.

## 9. Task Completion Protocol

- Run the smallest meaningful validation for the touched area.
- For theme/schedule changes, run `schedule_spec.lua` and `core_spec.lua`.
- For TUI changes, run `tui_spec.lua`.
- For state changes, run `state_spec.lua`.
- For system detection changes, run `system_spec.lua` and platform-specific specs.
- Sync `README.md`, `doc/colorful-times.txt`, and `CHANGELOG.md` whenever user-visible behavior changes.

---

## Agent skills

### Issue tracker

Issues live in GitHub Issues for this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

Triage labels use the default canonical vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context domain docs layout. See `docs/agents/domain.md`.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
