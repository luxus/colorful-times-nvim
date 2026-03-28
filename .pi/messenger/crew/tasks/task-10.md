# Extract Magic Numbers to Constants

Move magic numbers to named constants for maintainability.

**Implementation details:**
- In `schedule.lua`:
  - `1440` → `MINUTES_PER_DAY = 1440`
- In `core.lua`:
  - `5000` (default refresh_time) → use `M.config.refresh_time` (already defined in init.lua)
  - `60 * 1000` (min to ms) → `MS_PER_MINUTE = 60000`
- In `tui.lua`:
  - `200` (max colorschemes) → `MAX_COLORSCHEMES = 200`
  - `0.6`, `0.8` (window ratios) could be constants but less critical
- In `init.lua`:
  - Document that `5000` is `DEFAULT_REFRESH_TIME`

**Files to modify:**
- `lua/colorful-times/schedule.lua` - Add MINUTES_PER_DAY constant
- `lua/colorful-times/core.lua` - Add MS_PER_MINUTE constant
- `lua/colorful-times/tui.lua` - Add MAX_COLORSCHEMES constant
- `lua/colorful-times/init.lua` - Add DEFAULT_REFRESH_TIME constant

**Acceptance criteria:**
- No bare magic numbers in code (except 0, 1 for indexing)
- Constants defined at module level with clear names
- All existing tests pass
