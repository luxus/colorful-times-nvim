#!/usr/bin/env bash
set -euo pipefail

nvim --headless \
  -u tests/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"
