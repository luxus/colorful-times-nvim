# Autoresearch Ideas

- Measure `setup()` with a representative large schedule (for example 24 entries) if small-schedule startup stops improving; this can reveal validation/preprocess tradeoffs without overfitting to tiny configs.
- Consider a lazy command-dispatch table in `plugin/colorful-times.lua` only if `command_us` becomes a meaningful share of startup cost.
- Possible apply/startup tradeoff: precompute `_parsed_schedule` during setup for enabled non-empty schedules. This may reduce first-apply cost but reintroduces schedule.lua load into startup, so only try if apply becomes more important than startup parity.
