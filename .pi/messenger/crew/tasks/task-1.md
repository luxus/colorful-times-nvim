# Atomic State Writes in state.lua

Implement atomic state file writes using temp file + rename + fsync pattern to prevent corruption on crash.

**Implementation details:**
- Modify `state.save()` to:
  1. Write to temp file (same directory as target, name: `state.json.tmp.<pid>.<random>`)
  2. fsync the temp file to ensure data reaches disk
  3. Atomic rename temp → target
  4. Clean up temp file on any error
- Handle `vim.uv.fs_*` errors properly with detailed messages
- Ensure directory creation still happens before temp file creation

**Files to modify:**
- `lua/colorful-times/state.lua` - Rewrite save() function

**Acceptance criteria:**
- State writes are atomic (either complete or not present)
- Temp files are cleaned up on success and failure
- fsync ensures durability before rename
- All existing tests pass
- New test: Simulate crash during write, verify no corruption
