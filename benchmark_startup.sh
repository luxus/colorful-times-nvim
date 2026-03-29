#!/usr/bin/env bash
# Benchmark startup performance of colorful-times.nvim
set -e

cd "$(dirname "$0")"

# Run the benchmark with neovim
nvim --headless -u NONE --noplugin -l benchmark_startup.lua 2>&1
