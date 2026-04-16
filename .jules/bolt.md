## 2024-05-22: Background Preselection Optimization

- **Optimization**: Replaced `vim.iter` chains and hardcoded ternary logic with static lookup tables (`BG_OPTIONS`, `BG_MAP`) for background selection in TUI.
- **Impact**: Improved readability and maintainability. Eliminated redundant iterations and complex logical branches in `action_add` and `entry_form`.
- **Optimization**: Replaced `vim.iter(...):find()` with a direct `ipairs` loop in `pick_colorscheme` to ensure the correct 1-based index is returned for `snacks.picker`.
- **Performance**: Reduced overhead from closure allocations and iterator object creation in the TUI interaction paths.
