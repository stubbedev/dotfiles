#!/usr/bin/env bash

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

# Find the built-in monitor dynamically (usually eDP or LVDS)
builtin_monitor=$(hyprctl monitors | grep -i "eDP" | awk '{print $2}')
if [ -z "$builtin_monitor" ]; then
  builtin_monitor=$(hyprctl monitors | grep -i "LVDS" | awk '{print $2}')
fi

# Get the list of all active monitors
monitors=$(hyprctl monitors | grep "Monitor " | awk '{print $2}')
monitors=($monitors)

wspaces=$(hyprctl workspaces | grep "$builtin_monitor" | awk '{print $3}')
wspaces=($wspaces)
wspace_indices=("${!wspaces[@]}")
last_ws_index=${wspace_indices[-1]}
last_ws=${wspaces[$last_ws_index]}

if [ ${#monitors[@]} -gt 1 ]; then
  next_monitor=${monitors[1]}
  if [ "$action" == "close" ]; then
    for ws in "${wspaces[@]}"; do
      hyprctl dispatch moveworkspacetomonitor "$ws" "$next_monitor"
    done
    hyprctl dispatch dpms off "$builtin_monitor"
  fi
fi

if [ "$action" == "open" ]; then
  hyprctl dispatch dpms on "$builtin_monitor"
  hyprctl dispatch moveworkspacetomonitor "${last_ws}" "$builtin_monitor"
fi
