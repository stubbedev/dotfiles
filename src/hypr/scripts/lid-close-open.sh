#!/usr/bin/env bash

# Find the built-in monitor dynamically (usually eDP or LVDS)
builtin_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.name | test("eDP|LVDS")) | .name' | head -n1)

# Cache the monitor name for when it's disabled
if [ -n "$builtin_monitor" ]; then
  echo "$builtin_monitor" >/tmp/builtin_monitor
fi
if [ -z "$builtin_monitor" ] && [ -f /tmp/builtin_monitor ]; then
  builtin_monitor="$(cat /tmp/builtin_monitor)"
fi

# Exit if no built-in monitor found
if [ -z "$builtin_monitor" ]; then
  exit 0
fi

# Get the action (lid-close or lid-open)
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

# Count total monitors (including disabled ones if we have the cache)
monitor_count=$(hyprctl monitors -j | jq '. | length')

# When closing lid and docked, disable built-in display
if [ ${action} == "close" ] && [ "$monitor_count" -gt 1 ]; then
  hyprctl keyword monitor "$builtin_monitor", disable
fi

# When opening lid, enable built-in display
if [ "$action" == "open" ]; then
  hyprctl keyword monitor "$builtin_monitor", preferred, auto, 1.5
fi
