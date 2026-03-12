## 2024-05-15 - Unnecessary Sub-process Spawning in Timers
**Learning:** Polling the operating system (e.g. using `defaults` on macOS or `sh` on Linux) inside a periodic timer can cause significant performance overhead and high CPU usage if the result isn't even being used. In Neovim plugins using `vim.loop` (`uv`), this means unnecessary subprocesses are continually spawned.
**Action:** Always verify if a polled value is actively needed before initiating the expensive system call. Add early returns inside polling timers based on plugin configuration state.
