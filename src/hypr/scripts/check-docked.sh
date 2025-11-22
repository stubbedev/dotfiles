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

# If docked (more than 1 monitor), disable the built-in display
if [ "$monitor_count" -gt 1 ]; then
  hyprctl keyword monitor "$builtin_monitor", disable
fi
