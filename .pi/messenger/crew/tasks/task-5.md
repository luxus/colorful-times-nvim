# Add State Validation Before Save in state.lua

Validate data structure before writing to prevent persisting invalid state.

**Implementation details:**
- Create `validate_state(data)` function that checks:
  - `enabled` is boolean (if present)
  - `schedule` is array with valid entries (reuse schedule.validate_entry)
  - `refresh_time` is positive integer (if present)
  - `persist` is boolean (if present)
  - `default` is table with valid structure (if present)
  - `default.background` is one of "light", "dark", "system"
  - `default.colorscheme` is string
- Modify `state.save()` to call validation before writing
- Return error (don't write) if validation fails, notify user

**Files to modify:**
- `lua/colorful-times/state.lua` - Add validate_state() and integrate into save()

**Acceptance criteria:**
- Invalid state rejected with clear error message
- Valid state written successfully
- Partial state (only some fields) validates correctly
- All existing tests pass
- Add tests: Validation of invalid types, partial state, complete state
