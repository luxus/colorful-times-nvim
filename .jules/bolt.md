## 2024-05-15 - Unnecessary Sub-process Spawning in Timers
**Learning:** Polling the operating system (e.g. using `defaults` on macOS or `sh` on Linux) inside a periodic timer can cause significant performance overhead and high CPU usage if the result isn't even being used. In Neovim plugins using `vim.loop` (`uv`), this means unnecessary subprocesses are continually spawned.
**Action:** Always verify if a polled value is actively needed before initiating the expensive system call. Add early returns inside polling timers based on plugin configuration state.

## 2024-05-15 - GitHub Actions Cache 400 Error
**Learning:** Older versions of `leafo/gh-actions-lua` (like v9) use Node 20 and an outdated artifact API which returns `400 Bad Request` when trying to save or restore cache on modern runner images (ubuntu-latest 24.04+).
**Action:** Always update GitHub actions to the latest major version (`actions/checkout@v4`, `leafo/gh-actions-lua@v10`) when encountering cache 400 errors or Node 20 deprecation warnings.

## 2024-05-15 - Zero-blocking Neovim Startup with vim.uv
**Learning:** Neovim plugins that rely on system commands (e.g., getting OS light/dark mode) can block the Neovim UI rendering if done synchronously or via `vim.defer_fn()`.
**Action:** Always instantly apply a fallback configuration synchronously during `setup()` to avoid UI flashes. Execute the system check completely asynchronously using `vim.uv.spawn` and only trigger a colorscheme update if the detected background differs from the fallback. Also replace legacy `vim.loop` with modern `vim.uv` (Neovim 0.10+).

## 2024-05-16 - Heap Allocations in Hot Loops
**Learning:** Creating temporary tables (e.g., `local t = { val1, val2 }`) inside a loop causes per-iteration heap allocations. While modern GCs are fast, this creates unnecessary memory pressure and increases GC pause frequency in performance-sensitive code.
**Action:** Replace small iteration tables inside loops with unrolled logic or sequential local variable checks. In Lua, direct variable access and sequential comparisons are significantly faster than table creation and `ipairs` iteration.
