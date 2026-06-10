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
#   monitor.toggle.sh           one-shot reapply (manual / scripts)
#   monitor.toggle.sh daemon    long-running listener; reacts to DRM
#                               hotplug events from udev and to laptop
#                               lid toggles read from libinput

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

  local state
  state=$(grep -oEi 'open|closed' /proc/acpi/button/lid/*/state 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]' || echo "open")

  # On lid-close, disable eDP *and* re-pack the externals from 0,0 in a single
  # Lua pass. apply_reload (run before this in react) already re-enabled eDP
  # and auto-positioned the externals to its right; disabling eDP alone would
  # leave them stranded at a half-screen x offset. reflow_monitors(true) redoes
  # the whole layout with the panel gone, so the external no longer renders
  # offset by half. (`hyprctl keyword monitor "...,disable"` is rejected under
  # the Lua config — "keyword can't work with non-legacy parsers. Use eval." —
  # so drive it through the exposed Lua reflow_monitors instead.)
  if [ "$state" = "closed" ]; then
    hyprctl eval "reflow_monitors(true)" >/dev/null 2>&1 || true
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

# React to the laptop lid by reading the switch straight from libinput.
#
# Why not Hyprland's `bindl=,switch:Lid Switch,exec,...`: since the
# hyprland v0.55 / aquamarine 0.11 bump the lid SWITCH_TOGGLE no longer
# reaches Hyprland's keybind manager — libinput still processes it (the
# log shows "lid: suspending touchpad") but Hyprland never logs
# "Switch ... fired, triggering binds", so no dispatcher (lua or native)
# ever runs and the bind is dead. Reading libinput directly is the same
# compositor-independent approach already used for DRM hotplug below; the
# user is in the `input` group so no root is needed.
#
# react() reads the lid state from /proc and handles both directions
# (close -> disable eDP, open -> apply_reload re-enables it), so every
# toggle just calls react() regardless of the reported state.
listen_lid() {
  command -v libinput >/dev/null 2>&1 || return 0
  # Respawn if libinput exits, so a transient backend hiccup doesn't
  # silently kill lid handling for the rest of the session.
  while true; do
    stdbuf -oL libinput debug-events 2>/dev/null \
      | grep --line-buffered -iE 'switch_toggle.*lid' \
      | while IFS= read -r _; do react; done
    sleep 2
  done
}

listen_events() {
  local last_action=0

  # Initial sync so reality matches config after a Hyprland (re)start.
  react

  # Watch the lid in the background alongside the DRM hotplug loop.
  listen_lid &
  local lid_pid=$!
  trap 'kill "$lid_pid" 2>/dev/null' EXIT INT TERM

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
