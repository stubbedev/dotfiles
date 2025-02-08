#!/usr/bin/env bash

# Find the built-in monitor dynamically (usually eDP or LVDS)
builtin_monitor=$(hyprctl monitors | grep -i "eDP" | awk '{print $2}')
if [ -z "$builtin_monitor" ]; then
  builtin_monitor=$(hyprctl monitors | grep -i "LVDS" | awk '{print $2}')
fi
if [ -n "$builtin_monitor" ]; then
  echo "$builtin_monitor" >/tmp/builtin_monitor
fi
if [ -z "$builtin_monitor" ] && [ -f /tmp/builtin_monitor ]; then
  builtin_monitor="$(cat /tmp/builtin_monitor)"
fi

# Get the action (lid-close or lid-open) passed as an argument
function get_action {
  if [ ! -f /tmp/lid_closed ]; then
    touch /tmp/lid_closed
    echo "close"
  else
    rm -f /tmp/lid_closed
    echo "open"
  fi
}
action=$(get_action)

# Get the list of all active monitors
monitors=$(hyprctl monitors | grep "Monitor " | awk '{print $2}')
monitors=($monitors)

if [ ${#monitors[@]} -gt 1 ]; then
  if [ "$action" == "close" ]; then
    hyprctl keyword monitor "$builtin_monitor", disable
  fi
fi

if [ "$action" == "open" ]; then
  hyprctl keyword monitor "$builtin_monitor", enable
fi
