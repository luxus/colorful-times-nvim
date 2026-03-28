# Extract Linux Shell Script to Configurable Location

Make the inline Linux detection script configurable instead of hardcoded.

**Implementation details:**
- In `init.lua`, add new config option:
  - `system_background_detection_script` - string path to custom script or nil for default
- In `system.lua` `get_background()`:
  - Check if `config.system_background_detection_script` is set
  - If set, execute that script instead of inline script: `spawn_check("sh", { "-c", config.system_background_detection_script or default_script }, ...)`
  - If not set, use current inline script as default
- Document the script interface: exit 0 for dark, exit 1 for light
- Ensure script validation (file exists, executable) with clear error if invalid

**Files to modify:**
- `lua/colorful-times/init.lua` - Add system_background_detection_script to config
- `lua/colorful-times/system.lua` - Use configurable script or default inline script
- `doc/colorful-times.txt` - Document new config option

**Acceptance criteria:**
- Default behavior unchanged (inline script used)
- Custom script path respected when provided
- Proper error handling for missing/non-executable scripts
- All existing tests pass
- Add test: Verify custom script execution, verify fallback to default
