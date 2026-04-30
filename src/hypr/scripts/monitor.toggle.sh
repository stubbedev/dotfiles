#!/usr/bin/env bash

# Toggle the built-in monitor based on the lid switch state.
#
# Usage:
#   monitor.toggle.sh           one-shot toggle (used by the lid switch bind)
#   monitor.toggle.sh daemon    long-running listener that re-runs the toggle
#                               on Hyprland monitoradded/monitorremoved events
#                               (e.g. when a Thunderbolt dock is unplugged)

apply_toggle() {
  local monitors builtin_monitor state currently_disabled current_scale
  monitors=$(hyprctl monitors all -j)
  builtin_monitor=$(echo "$monitors" | jq -r '.[] | select(.name | test("eDP|LVDS")) | .name' | head -n1)

  [ -z "$builtin_monitor" ] && return 0

  state=$(grep -oEi 'open|closed' /proc/acpi/button/lid/*/state 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]' || echo "open")

  currently_disabled=$(echo "$monitors" | jq -r --arg m "$builtin_monitor" '.[] | select(.name == $m) | .disabled')
  current_scale=$(echo "$monitors" | jq -r --arg m "$builtin_monitor" '.[] | select(.name == $m) | .scale')

  if [ "$state" = "open" ] && { [ "$currently_disabled" = "true" ] || [ "$current_scale" != "1.50" ]; }; then
    hyprctl keyword monitor "$builtin_monitor", preferred, auto, 1.5
  fi

  if [ "$state" = "closed" ] && [ "$currently_disabled" != "true" ]; then
    hyprctl keyword monitor "$builtin_monitor", disable
  fi
}

listen_events() {
  local sock="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

  apply_toggle

  while true; do
    if [ ! -S "$sock" ]; then
      sleep 1
      continue
    fi

    socat -u UNIX-CONNECT:"$sock" - 2>/dev/null | while IFS= read -r line; do
      case "$line" in
        monitoradded*|monitorremoved*) apply_toggle ;;
        *) ;;
      esac
    done

    sleep 1
  done
}

if [ "${1:-}" = "daemon" ]; then
  listen_events
else
  apply_toggle
fi
