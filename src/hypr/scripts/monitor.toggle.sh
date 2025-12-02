#!/usr/bin/env bash

# Find the built-in monitor dynamically (usually eDP or LVDS)
builtin_monitor=$(hyprctl monitors all -j | jq -r '.[] | select(.name | test("eDP|LVDS")) | .name' | head -n1)

# Exit if no built-in monitor found
if [ -z "$builtin_monitor" ]; then
  exit 0
fi

# Get the action (lid-close or lid-open)
state=$(grep -oEi 'open|closed' /proc/acpi/button/lid/*/state 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]' || echo "open")

if [ "$state" == "open" ]; then
  hyprctl keyword monitor "$builtin_monitor", preferred, auto, 1.5
fi

if [ "$state" == "closed" ]; then
  hyprctl keyword monitor "$builtin_monitor", disable
fi
