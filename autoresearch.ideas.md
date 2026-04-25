# Autoresearch Ideas

- Measure `setup()` with a representative large schedule (for example 24 entries) if small-schedule startup stops improving; this can reveal validation/preprocess tradeoffs without overfitting to tiny configs.
- Consider a lazy command-dispatch table in `plugin/colorful-times.lua` only if `command_us` becomes a meaningful share of startup cost.
