#!/usr/bin/env bash
# Aerc viewer pager: write the (already-filtered) message body to a temp
# file with a .md suffix and open it in nvim read-only. Markdown gets
# native syntax highlighting; plain-text emails fall back gracefully.
set -euo pipefail

tmp=$(mktemp --suffix=.md /tmp/aerc-XXXXXX)
trap 'rm -f "$tmp"' EXIT

cat > "$tmp"

exec nvim -R \
  -c 'set noswapfile nomodifiable nomodified' \
  -c 'set filetype=markdown' \
  "$tmp"
