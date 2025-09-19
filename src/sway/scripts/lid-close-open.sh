#!/usr/bin/env bash

# Find the built-in monitor dynamically (usually eDP or LVDS)
builtin_monitor=$(swaymsg -t get_outputs | jq -r '.[] | select(.name | contains("eDP")) | .name')
if [ -z "$builtin_monitor" ]; then
  builtin_monitor=$(swaymsg -t get_outputs | jq -r '.[] | select(.name | contains("LVDS")) | .name')
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
monitors=$(swaymsg -t get_outputs | jq -r '.[] | select(.active == true) | .name')
monitors=($monitors)

if [ ${#monitors[@]} -gt 1 ]; then
  if [ "$action" == "close" ]; then
    swaymsg output "$builtin_monitor" disable
  fi
fi

if [ "$action" == "open" ]; then
  swaymsg output "$builtin_monitor" enable
fi