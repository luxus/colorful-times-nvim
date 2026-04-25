# Autoresearch Ideas

- Consider a lazy command-dispatch table in `plugin/colorful-times.lua` only if `command_us` becomes a meaningful share of startup cost.
- Possible apply/startup tradeoff: precompute `_parsed_schedule` during setup for enabled non-empty schedules. This may reduce first-apply cost but reintroduces schedule.lua load into startup, so only try if apply becomes more important than startup parity.
