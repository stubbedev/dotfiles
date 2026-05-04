#!/usr/bin/env bash
# Adjust monitor brightness. Prefers brightnessctl (internal/backlight) and
# falls back to ddcutil for external monitors.

set -euo pipefail

action=${1:-}
step=10
min=5

if [ -z "$action" ]; then
  echo "Usage: $0 [increase|decrease]" >&2
  exit 1
fi

# Try internal/backlight first via brightnessctl
if command -v brightnessctl >/dev/null 2>&1; then
  device=$(brightnessctl --list --class backlight --machine 2>/dev/null | awk -F, 'NR==1 {print $1}')
  if [ -n "$device" ]; then
    current_pct=$(brightnessctl --device "$device" --machine info 2>/dev/null | awk -F, 'NR==1 {gsub(/%/, "", $4); print $4}')
    if [ -z "$current_pct" ]; then
      echo "Could not read current brightness" >&2
      exit 1
    fi

    if [ "$action" = "increase" ]; then
      new=$((current_pct + step))
      [ "$new" -gt 100 ] && new=100
    elif [ "$action" = "decrease" ]; then
      new=$((current_pct - step))
      [ "$new" -lt "$min" ] && new=$min
    else
      echo "Invalid argument. Use 'increase' or 'decrease'" >&2
      exit 1
    fi

    brightnessctl --device "$device" set "${new}%"
    exit 0
  fi
fi

# Fallback to external monitors via ddcutil
if command -v ddcutil >/dev/null 2>&1; then
  current=$(ddcutil getvcp 10 --brief 2>/dev/null | awk 'NR==1 {print $3}')
  if [ -n "${current:-}" ]; then
    if [ "$action" = "increase" ]; then
      new=$((current + step))
      if [ "$new" -gt 100 ]; then
        new=100
      fi
    elif [ "$action" = "decrease" ]; then
      new=$((current - step))
      if [ "$new" -lt "$min" ]; then
        new=$min
      fi
    else
      echo "Invalid argument. Use 'increase' or 'decrease'" >&2
      exit 1
    fi

    exec ddcutil setvcp 10 "$new"
  fi
fi

echo "No brightness controller found" >&2
exit 1
