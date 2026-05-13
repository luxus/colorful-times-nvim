# Colorful Times

Colorful Times is a Neovim plugin that chooses a colorscheme and background from a user-defined theme schedule, the default theme, optional system background detection, and a session hold. The project language distinguishes requested values from resolved values so runtime behavior, status output, and TUI preview stay consistent.

## Language

**Theme schedule**:
A set of time ranges that may choose a colorscheme and requested background for the current wall-clock time.
_Avoid_: timetable, theme list, schedule config

**Schedule runtime**:
The internal implementation that parses, validates, preprocesses, and queries the **Theme schedule** for **Theme resolution**, state validation, and health checks. It is not a public user interface.
_Avoid_: schedule API, public schedule module

**Theme resolution**:
The policy that chooses the active colorscheme, requested background, resolved background, and source from the theme schedule, default theme, system background detection, and session hold.
_Avoid_: theme selection, colorscheme logic, style calculation

**Default theme**:
The fallback colorscheme, requested background, and optional light/dark overrides used when no theme schedule entry is active or the plugin is disabled.
_Avoid_: fallback config, base theme

**Requested background**:
The background value chosen by a theme schedule entry, default theme, or session hold before system background detection is applied.
_Avoid_: configured background, raw background

**Resolved background**:
The concrete `light` or `dark` background that Neovim should apply after interpreting a requested `system` background.
_Avoid_: effective background, detected background

**System background detection**:
The platform-specific mechanism that resolves a requested `system` background to `light` or `dark`.
_Avoid_: OS theme detection, auto background

**Detection plan**:
The backend-specific description of how to perform **System background detection**, including backend identity, executable requirements, command details, and fallback behavior, before any process is run.
_Avoid_: detection config, backend info

**Session hold**:
A runtime-only override that pins the current or previewed theme until released or Neovim exits.
_Avoid_: session pin, lock, override

**Preview target**:
The colorscheme and resolved background that the TUI applies temporarily while editing a theme schedule entry or default theme, without invoking async system background detection.
_Avoid_: preview state, draft theme

**TUI action policy**:
The state machine that turns a TUI user action and current TUI state into new TUI state plus effect intents, without applying preview, persistence, core theme effects, or rendering directly.
_Avoid_: action handlers, UI callbacks

**Effect intent**:
A data description of a side effect requested by **TUI action policy**, such as preview, persistence, core theme effects, rendering, or user message display.
_Avoid_: side-effect call, callback

**Render plan**:
The complete data needed to draw the TUI, including lines, marks, cursor position, window size, extmark intents, and highlight intents, built from explicit inputs before Neovim buffer/window APIs are called.
_Avoid_: rendered buffer, screen output

**Persisted state policy**:
The internal policy that decodes, validates, encodes, and merges persisted Colorful Times state bytes without reading or writing files.
_Avoid_: state file IO, persistence service

**State filesystem adapter**:
The implementation that reads persisted state bytes, writes them atomically, and backs up corrupt files. It does not decide persisted shape or merge rules.
_Avoid_: state policy, persistence rules

## Relationships

- A **Theme schedule** contains zero or more entries; at most one active entry feeds **Theme resolution** at a given wall-clock minute.
- **Schedule runtime** is an internal implementation detail; public callers should use **Theme resolution** rather than depending on schedule parsing or cache behavior.
- **Theme resolution** falls back to the **Default theme** when no **Theme schedule** entry is active or when scheduling is disabled.
- A **Requested background** of `system` requires **System background detection** to produce a **Resolved background**.
- A **Detection plan** lets core execute **System background detection** without duplicating backend selection rules.
- A **Session hold** bypasses the **Theme schedule** and **Default theme** while it is active.
- A **Preview target** uses the same **Theme resolution** fallback rules as runtime application, but it only consumes a known **Resolved background** instead of invoking **System background detection**.
- **TUI action policy** produces **Effect intents**; TUI adapters execute those intents against preview, persistence, core theme effects, and rendering.
- A **Render plan** is built from explicit config, status, current minute, current colorscheme/background, and a Vim display-width Adapter before the render Adapter mutates Neovim buffers or windows.
- **Persisted state policy** owns bytes-to-state and state-to-bytes rules; the **State filesystem adapter** owns filesystem effects only.

## Example dialogue

> **Dev:** "If a **Theme schedule** entry requests `system`, should the TUI preview use the current Neovim background or call **System background detection** again?"
> **Domain expert:** "Use **Theme resolution** rules to produce the **Preview target**, but do not invoke async **System background detection** from preview. The TUI should consume a known **Resolved background** and apply it temporarily."

## Flagged ambiguities

- "background" can mean either **Requested background** (`light`, `dark`, or `system`) or **Resolved background** (`light` or `dark`). Prefer the explicit term when discussing architecture or tests.
