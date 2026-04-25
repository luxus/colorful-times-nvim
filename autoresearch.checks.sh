#!/usr/bin/env bash
set -euo pipefail

minimal_lines=$(wc -l < bench/minimal-switcher.lua | tr -d ' ')
if [ "$minimal_lines" -gt 50 ]; then
  echo "bench/minimal-switcher.lua must stay under 50 lines (found $minimal_lines)" >&2
  exit 1
fi

nvim --headless \
  -u tests/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"
