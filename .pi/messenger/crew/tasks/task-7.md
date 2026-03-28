# Add setup() Input Validation in core.lua

Validate user input types in `setup()` to catch configuration errors early.

**Implementation details:**
- Create validation helpers or inline checks for:
  - `opts.enabled` - must be boolean if present
  - `opts.refresh_time` - must be positive integer >= 1000 if present
  - `opts.persist` - must be boolean if present
  - `opts.schedule` - must be array, each entry valid via schedule.validate_entry
  - `opts.default.background` - must be "light", "dark", or "system" if present
  - `opts.system_background_detection` - must be nil, function, or non-empty array of strings
- Validate before any merging or state loading
- Return early with `vim.notify` error if validation fails
- Don't modify config if validation fails

**Files to modify:**
- `lua/colorful-times/core.lua` - Add validation at start of setup()

**Acceptance criteria:**
- Invalid types rejected with clear error before any state changes
- Valid configuration proceeds normally
- All existing tests pass
- Add tests: Invalid enabled type, invalid refresh_time, invalid schedule entry, invalid background
