#!/bin/bash

# Launch waybar with proper Wayland environment detection.
# Sets HYPRLAND_INSTANCE_SIGNATURE only when an active Hyprland socket is
# found; on niri (or any other Wayland compositor) we skip Hyprland detection
# and proceed — waybar's hyprland module just stays inactive there.

CURRENT_INSTANCE=""
attempt=0

if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
  socket_path="/run/user/$(id -u)/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock"
  if [ -S "$socket_path" ]; then
    CURRENT_INSTANCE="$HYPRLAND_INSTANCE_SIGNATURE"
  fi
fi

# Only spend time scanning for a Hyprland instance if we look like a
# Hyprland session; otherwise jump straight to launching waybar.
if [ -z "$CURRENT_INSTANCE" ] && [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ]; then
  while [ $attempt -lt 50 ] && [ -z "$CURRENT_INSTANCE" ]; do
    for lockfile in $(ls -t /run/user/$(id -u)/hypr/*/hyprland.lock 2>/dev/null); do
      instance_dir=$(dirname "$lockfile")
      instance_name=$(basename "$instance_dir")
      socket_path="$instance_dir/.socket.sock"

      if [ -S "$socket_path" ]; then
        CURRENT_INSTANCE="$instance_name"
        break
      fi
    done

    if [ -z "$CURRENT_INSTANCE" ]; then
      sleep 0.1
    fi
    attempt=$((attempt + 1))
  done
fi

if [ -n "$CURRENT_INSTANCE" ]; then
  export HYPRLAND_INSTANCE_SIGNATURE="$CURRENT_INSTANCE"
fi

# A Wayland socket file alone isn't proof a compositor is alive — when a
# compositor exits abnormally (or libwayland falls back to wayland-2 because
# wayland-1 is taken, then exits) the socket file lingers. libwayland's lock
# file is held with flock by the live compositor, so a non-blocking flock
# that succeeds means nobody owns the socket.
_wayland_live() {
  local display="$1"
  local sock="$XDG_RUNTIME_DIR/$display"
  local lock="$XDG_RUNTIME_DIR/$display.lock"
  [ -S "$sock" ] || return 1
  [ -e "$lock" ] || return 1
  ! flock -n -x "$lock" true 2>/dev/null
}

# Auto-detect WAYLAND_DISPLAY if not set or if the socket is stale.
if [ -n "$WAYLAND_DISPLAY" ] && _wayland_live "$WAYLAND_DISPLAY"; then
  :
else
  unset WAYLAND_DISPLAY
  attempt=0
  while [ $attempt -lt 50 ] && [ -z "$WAYLAND_DISPLAY" ]; do
    for socket in $(ls -t "$XDG_RUNTIME_DIR"/wayland-[0-9]* 2>/dev/null | grep -E 'wayland-[0-9]+$'); do
      candidate=$(basename "$socket")
      if _wayland_live "$candidate"; then
        export WAYLAND_DISPLAY="$candidate"
        break
      fi
    done

    if [ -z "$WAYLAND_DISPLAY" ]; then
      sleep 0.1
    fi
    attempt=$((attempt + 1))
  done
fi

if [ -z "$WAYLAND_DISPLAY" ] || ! _wayland_live "$WAYLAND_DISPLAY"; then
  echo "No live Wayland compositor found, retrying via systemd" >&2
  exit 1
fi

# Launch waybar directly (not using exec to keep the shell process)
# This way waybar inherits the environment variables we just set
waybar
