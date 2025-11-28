#!/usr/bin/env bash

# Wait a moment for monitors to be detected
sleep 2

# Find the built-in monitor
builtin_monitor=$(hyprctl monitors | grep -i "eDP" | awk '{print $2}')
if [ -z "$builtin_monitor" ]; then
  builtin_monitor=$(hyprctl monitors | grep -i "LVDS" | awk '{print $2}')
fi

# If no built-in monitor found, exit
if [ -z "$builtin_monitor" ]; then
  exit 0
fi

# Count total monitors
monitor_count=$(hyprctl monitors -j | jq '. | length')

# Determine lid state if possible (default to "open" when unknown)
lid_state="open"
if [ -d /proc/acpi/button/lid ]; then
  lid_state=$(grep -oEi 'open|closed' /proc/acpi/button/lid/*/state 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]' || echo "open")
fi

# Log for debugging
logger -t check-docked "lid_state=${lid_state} monitors=${monitor_count} builtin=${builtin_monitor}"

# If docked (more than 1 monitor):
# - enable the built-in monitor only if the lid is closed
# - otherwise disable the built-in monitor
if [ "$monitor_count" -gt 1 ]; then
  if [ "$lid_state" = "closed" ]; then
    hyprctl keyword monitor "$builtin_monitor", enable
  else
    hyprctl keyword monitor "$builtin_monitor", disable
  fi
fi
