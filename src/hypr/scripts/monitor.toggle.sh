#!/usr/bin/env bash

# React to display and lid events by reloading Hyprland's config.
#
# Hyprland's built-in monitor-rule reapplication on hotplug is unreliable
# (notably on Thunderbolt dock unplug): waybar surfaces stay bound to the
# departed output (renders as solid color), the cursor reverts to the
# default theme, and per-monitor scale/position can drift from monitors.conf.
# `hyprctl reload` rebinds layer-shell surfaces, reissues setcursor, and
# re-applies every `monitor =` rule in one shot — the only command observed
# to recover the session without restarting Hyprland.
#
# Why udev, not socket2:
#   Hyprland's own monitoradded/monitorremoved events on socket2 are
#   well-known to fire unreliably — see hyprwm/Hyprland#1341 ("~10% of
#   the time") and discussion #5644 which recommends udev DRM events as
#   the canonical hotplug signal. udev sees the kernel-level HOTPLUG=1
#   uevent for every DRM card connector change, with no compositor in
#   the path. The same script remains usable on any Wayland compositor.
#
# Loop guard:
#   `hyprctl reload` itself doesn't emit udev events, so unlike the
#   previous socket2 design we have no inherent feedback loop. The 1s
#   debounce remains to collapse the short udev burst the kernel emits
#   when multiple connectors flap together (common on dock unplug).
#
# Usage:
#   monitor.toggle.sh           one-shot (used by the lid switch bind)
#   monitor.toggle.sh daemon    long-running listener; reacts to DRM
#                               hotplug events from udev

# Re-apply Hyprland's full config. Reloads monitors, layer-shell, cursor.
apply_reload() {
  hyprctl reload >/dev/null 2>&1 || true
}

# Disable the built-in panel when the lid is closed. The open case is
# handled implicitly by apply_reload above, which re-applies the eDP rule
# from monitors.conf and brings the panel back to its configured state.
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
  apply_reload
  apply_lid
}

# Restart WirePlumber so it re-evaluates ALSA card availability after a
# dock/undock. Without this, HDMI/DP sinks tied to the dock can linger as
# unavailable or fail to reappear in pavucontrol until the next login.
restart_wireplumber() {
  systemctl --user restart wireplumber.service >/dev/null 2>&1 || true
}

listen_events() {
  local last_action=0

  # Initial sync so reality matches config after a Hyprland (re)start.
  react

  # udevadm emits one HOTPLUG=1 property line per DRM hotplug uevent.
  # Process substitution keeps `last_action` in this shell rather than
  # the subshell that a pipe would create.
  while IFS= read -r line; do
    [ "$line" = "HOTPLUG=1" ] || continue

    now=$(date +%s)
    if [ $((now - last_action)) -lt 1 ]; then
      continue
    fi
    react
    restart_wireplumber
    last_action=$(date +%s)
  done < <(udevadm monitor --property --udev --subsystem-match=drm 2>/dev/null)
}

if [ "${1:-}" = "daemon" ]; then
  listen_events
else
  react
fi
