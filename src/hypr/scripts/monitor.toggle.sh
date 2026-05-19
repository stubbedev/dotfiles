#!/usr/bin/env bash

# React to display and lid events by reapplying the monitor config.
#
# Hyprland's built-in monitor-rule reapplication on hotplug is unreliable
# (notably on Thunderbolt dock unplug): outputs end up in a stuck single-color
# state, geometry doesn't match the rule, or the workspace lands on a now-gone
# output. We work around that by re-feeding every "monitor =" line from
# monitors.conf back to Hyprland via `hyprctl keyword monitor` on each event.
# Hyprland recomputes geometry from scratch and the output recovers.
#
# Usage:
#   monitor.toggle.sh           one-shot (used by the lid switch bind)
#   monitor.toggle.sh daemon    long-running listener; runs the same logic
#                               on Hyprland monitoradded/monitorremoved events

MONITORS_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/monitors.conf"

# Re-feed every "monitor = <spec>" line back to hyprctl. Idempotent in
# steady state — Hyprland skips no-op changes — but each real change does
# re-emit monitoradded/monitorremoved, so callers must debounce.
apply_monitors() {
  [ -r "$MONITORS_CONF" ] || return 0

  local line spec
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
      monitor*=*)
        spec="${line#*=}"
        spec="${spec#"${spec%%[![:space:]]*}"}"
        hyprctl keyword monitor "$spec" >/dev/null 2>&1 || true
        ;;
    esac
  done < "$MONITORS_CONF"
}

# Disable the built-in panel when the lid is closed. Re-enable is handled
# implicitly by apply_monitors above (it reapplies the eDP rule from config).
apply_lid() {
  # ACPI lid bind fires before /proc/acpi/button/lid/*/state updates on some
  # hardware (notably when docked via Thunderbolt). Brief sleep avoids reading
  # the previous lid state and toggling the wrong direction.
  sleep 0.3

  local state builtin
  state=$(grep -oEi 'open|closed' /proc/acpi/button/lid/*/state 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]' || echo "open")
  builtin=$(hyprctl monitors all -j | jq -r '.[] | select(.name | test("eDP|LVDS")) | .name' | head -n1)

  [ -z "$builtin" ] && return 0

  if [ "$state" = "closed" ]; then
    hyprctl keyword monitor "$builtin, disable" >/dev/null 2>&1 || true
  fi
}

react() {
  apply_monitors
  apply_lid
}

listen_events() {
  local sock="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
  local last_action=0

  # Initial sync so reality matches config after a Hyprland (re)start.
  react

  while true; do
    if [ ! -S "$sock" ]; then
      sleep 1
      continue
    fi

    while IFS= read -r line; do
      case "$line" in
        monitoradded*|monitorremoved*)
          # Debounce: our own apply_monitors call re-emits monitor events for
          # every rule it changes. Without this window we'd recurse on every
          # dock plug/unplug. 2s comfortably covers the cascade.
          now=$(date +%s)
          if [ $((now - last_action)) -lt 2 ]; then
            continue
          fi
          react
          last_action=$(date +%s)
          ;;
        *) ;;
      esac
    done < <(socat -u UNIX-CONNECT:"$sock" - 2>/dev/null)

    sleep 1
  done
}

if [ "${1:-}" = "daemon" ]; then
  listen_events
else
  react
fi
