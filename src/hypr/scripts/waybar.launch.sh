#!/bin/bash

# Launch waybar with proper Hyprland environment detection
# This ensures waybar can communicate with Hyprland for workspace updates

# Auto-detect the current active Hyprland instance (wait briefly if needed)
CURRENT_INSTANCE=""
attempt=0

if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
  socket_path="/run/user/$(id -u)/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock"
  if [ -S "$socket_path" ] && ss -xl | grep -q "$socket_path"; then
    CURRENT_INSTANCE="$HYPRLAND_INSTANCE_SIGNATURE"
  fi
fi

while [ $attempt -lt 50 ] && [ -z "$CURRENT_INSTANCE" ]; do
  CURRENT_INSTANCE=""
  for lockfile in $(ls -t /run/user/$(id -u)/hypr/*/hyprland.lock 2>/dev/null); do
    instance_dir=$(dirname "$lockfile")
    instance_name=$(basename "$instance_dir")
    socket_path="$instance_dir/.socket.sock"

    if [ -S "$socket_path" ] && ss -xl | grep -q "$socket_path"; then
      CURRENT_INSTANCE="$instance_name"
      break
    fi
  done

  if [ -z "$CURRENT_INSTANCE" ]; then
    sleep 0.1
  fi
  attempt=$((attempt + 1))
done

if [ -n "$CURRENT_INSTANCE" ]; then
  export HYPRLAND_INSTANCE_SIGNATURE="$CURRENT_INSTANCE"
else
  echo "No Hyprland socket found, retrying via systemd" >&2
  exit 1
fi

# Auto-detect WAYLAND_DISPLAY if not set (wait briefly if needed)
if [ -n "$WAYLAND_DISPLAY" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
  :
elif [ -z "$WAYLAND_DISPLAY" ]; then
  attempt=0
  while [ $attempt -lt 50 ] && [ -z "$WAYLAND_DISPLAY" ]; do
    for socket in $(ls -t "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v ".lock"); do
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
