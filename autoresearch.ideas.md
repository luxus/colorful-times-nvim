# Autoresearch Ideas

- Larger structural split: move rare public APIs (status/pin/session/open/reload) out of `core.lua` while preserving shared runtime state. Status-only split was not enough; broader split may help core parse time but needs careful tests.
- Schedule runtime split: move hot parse/preprocess/lookup functions into a smaller runtime module while keeping `colorful-times.schedule` as public wrapper. Likely affects apply/resolve more than current startup primary.
