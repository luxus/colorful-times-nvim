#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
xdg_home="$(mktemp -d)"
trap 'rm -rf "$xdg_home"' EXIT
export XDG_DATA_HOME="$xdg_home/data"
export XDG_STATE_HOME="$xdg_home/state"
export XDG_CACHE_HOME="$xdg_home/cache"
export CT_BENCH_SAMPLES="${CT_BENCH_SAMPLES:-31}"
export CT_BENCH_WARMUP="${CT_BENCH_WARMUP:-3}"
export CT_BENCH_STARTUP_ITERS="${CT_BENCH_STARTUP_ITERS:-5}"
export CT_BENCH_APPLY_ITERS="${CT_BENCH_APPLY_ITERS:-100}"
export CT_BENCH_COMMAND_ITERS="${CT_BENCH_COMMAND_ITERS:-10}"
export CT_BENCH_RESOLVE_ITERS="${CT_BENCH_RESOLVE_ITERS:-20000}"

nvim --headless -u NONE --noplugin \
  --cmd "set rtp^=$root" \
  -c "luafile $root/bench/autoresearch_minimal_compare.lua" \
  -c 'qa!'
