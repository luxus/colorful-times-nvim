# Autoresearch Ideas

- Larger structural split: move rare public APIs (status/pin/session/reload) out of `core.lua` while preserving shared runtime state. Status-only split was not enough and moving `open()` alone failed checks; only revisit with a coherent API boundary plus tests.
