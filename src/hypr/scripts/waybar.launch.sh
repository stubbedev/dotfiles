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

# Auto-detect WAYLAND_DISPLAY if not set or if the socket no longer exists
if [ -n "$WAYLAND_DISPLAY" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
  :
else
  unset WAYLAND_DISPLAY
  attempt=0
  while [ $attempt -lt 50 ] && [ -z "$WAYLAND_DISPLAY" ]; do
    for socket in $(ls -t "$XDG_RUNTIME_DIR"/wayland-[0-9]* 2>/dev/null | grep -E 'wayland-[0-9]+$'); do
      if [ -S "$socket" ]; then
        export WAYLAND_DISPLAY=$(basename "$socket")
        break
      fi
    done

    if [ -z "$WAYLAND_DISPLAY" ]; then
      sleep 0.1
    fi
    attempt=$((attempt + 1))
  done
fi

if [ -z "$WAYLAND_DISPLAY" ] || [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
  echo "No Wayland socket found, retrying via systemd" >&2
  exit 1
fi

# Launch waybar directly (not using exec to keep the shell process)
# This way waybar inherits the environment variables we just set
waybar
