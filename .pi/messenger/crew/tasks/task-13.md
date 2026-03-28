# Add Backup for Corrupted State Files

When `state.load()` encounters a parse error, backup the corrupted file before returning empty state.

**Implementation details:**
- Modify `state.load()` error handling:
  - When `pcall(vim.json.decode)` fails:
    1. Generate backup path: `path .. ".bak." .. os.time()`
    2. Use `vim.uv.fs_rename(path, backup)` to move corrupted file to backup
    3. If rename fails, try copy+delete fallback
    4. Notify user: "colorful-times: corrupted state backed up to <path>"
  5. Return empty table as before
- Keep only last N backups (optional cleanup, e.g., keep last 5)
- Ensure backup doesn't overwrite existing (use timestamp)

**Files to modify:**
- `lua/colorful-times/state.lua` - Add backup logic to load() error handler

**Acceptance criteria:**
- Corrupted state file preserved with .bak.<timestamp> suffix
- User notified of backup location
- Fresh empty state returned for new configuration
- Multiple corruptions create multiple backups
- All existing tests pass
- Add test: Simulate corruption, verify backup created
