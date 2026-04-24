# Changelog

## 3.0.0 - 2026-04-24

### Added
- Added a redesigned inline TUI for managing schedule entries and default theme settings in a single floating window.
- Added live theme and background previews while editing schedules and defaults.
- Added inline colorscheme and background selectors with filter support and live preview updates.
- Added runtime session holds so users can pin the current or draft theme for the current Neovim session.
- Added discard confirmation for dirty schedule edits before leaving edit mode.

### Changed
- Made the TUI layout more compact and responsive across narrower editor widths.
- Moved the title, version, current time, status, source, and full-width day timeline into the framed header.
- Improved TUI highlighting for status, source, selected rows, active rows, and preview values.
- Replaced the README ASCII mockup with an actual TUI screenshot.

### Fixed
- Fixed clipped or inconsistent section widths in narrow windows.
- Fixed Unicode display-width handling for highlights and cursor placement.
- Fixed theme selector input so common colorscheme names can be filtered correctly.
- Fixed preview summary updates while moving through theme selector choices.
