#!/usr/bin/env bash
# Bridge niri's geometric default into focus-history behavior:
# whenever a window closes, dispatch focus-window-previous so niri jumps
# back to whatever was focused before the now-closed window, instead of
# the column to its right.
set -euo pipefail

niri msg --json event-stream | while IFS= read -r line; do
  if [[ "$line" == *'"WindowClosed"'* ]]; then
    niri msg action focus-window-previous >/dev/null 2>&1 || true
  fi
done
