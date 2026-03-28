# Fix Partial Config Merge in state.lua

Extend `merge()` to handle all config keys that can be persisted, not just `schedule` and `enabled`.

**Implementation details:**
- Modify `state.merge(base_config, stored)` to also merge:
  - `stored.refresh_time` → `result.refresh_time`
  - `stored.persist` → `result.persist`
  - `stored.default` (deep merge):
    - `stored.default.colorscheme` → `result.default.colorscheme`
    - `stored.default.background` → `result.default.background`
    - `stored.default.themes` → `result.default.themes` (deep)
- Use `vim.tbl_deep_extend("force", ...)` for default table merging
- Ensure nil values in stored don't overwrite base (preserve current nil-check pattern)
- Ensure empty tables (like `schedule = {}`) still overwrite base

**Files to modify:**
- `lua/colorful-times/state.lua` - Extend merge() function

**Acceptance criteria:**
- `refresh_time` from stored applies correctly
- `persist` from stored applies correctly
- `default.colorscheme` from stored applies correctly
- `default.background` from stored applies correctly
- `default.themes` from stored applies correctly
- Missing keys in stored don't affect base
- Empty arrays still overwrite (regression test)
- Tests in state_spec.lua that currently document BUGs should now pass
