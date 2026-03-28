# Improve io.open Error Messages Using vim.uv.fs_open

Replace `io.open` with `vim.uv.fs_open` for better error information in file operations.

**Implementation details:**
- In `state.lua` `save()` and `load()`:
  - Replace `io.open(path, "w")` with `vim.uv.fs_open(path, flags, mode)`
  - Use flags: `uv.constants.O_WRONLY | uv.constants.O_CREAT | uv.constants.O_TRUNC` for save
  - Use flags: `uv.constants.O_RDONLY` for load
  - Mode: ` tonumber("644", 8)` (0644 permissions)
  - On error, `vim.uv.fs_open` returns nil + error code/name
  - Convert error codes to human-readable messages:
    - `EACCES` → "Permission denied"
    - `ENOENT` → "Directory does not exist"
    - `ENOSPC` → "Disk full"
    - `EROFS` → "Read-only filesystem"
    - etc.
- Ensure proper file descriptor closing with `vim.uv.fs_close()`

**Files to modify:**
- `lua/colorful-times/state.lua` - Replace io.open with vim.uv.fs_open in save() and load()

**Acceptance criteria:**
- Specific error messages (e.g., "Permission denied" instead of generic "could not write")
- Proper file descriptor lifecycle management
- Atomic write compatibility (Task 1 uses uv.fs_* functions already)
- All existing tests pass
