## 2024-05-15 - Unnecessary Sub-process Spawning in Timers
**Learning:** Polling the operating system (e.g. using `defaults` on macOS or `sh` on Linux) inside a periodic timer can cause significant performance overhead and high CPU usage if the result isn't even being used. In Neovim plugins using `vim.loop` (`uv`), this means unnecessary subprocesses are continually spawned.
**Action:** Always verify if a polled value is actively needed before initiating the expensive system call. Add early returns inside polling timers based on plugin configuration state.

## 2024-05-15 - GitHub Actions Cache 400 Error
**Learning:** Older versions of `leafo/gh-actions-lua` (like v9) use Node 20 and an outdated artifact API which returns `400 Bad Request` when trying to save or restore cache on modern runner images (ubuntu-latest 24.04+).
**Action:** Always update GitHub actions to the latest major version (`actions/checkout@v4`, `leafo/gh-actions-lua@v10`) when encountering cache 400 errors or Node 20 deprecation warnings.
