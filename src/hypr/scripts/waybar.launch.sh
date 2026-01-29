#!/bin/bash

# Launch waybar with proper Hyprland environment detection
# This ensures waybar can communicate with Hyprland for workspace updates

# Auto-detect the current active Hyprland instance
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

# Fallback to newest lock file if no listening socket found
if [ -z "$CURRENT_INSTANCE" ]; then
  CURRENT_INSTANCE=$(ls -t /run/user/$(id -u)/hypr/*/hyprland.lock 2>/dev/null | head -1 | xargs dirname 2>/dev/null | xargs basename 2>/dev/null)
fi

if [ -n "$CURRENT_INSTANCE" ]; then
  export HYPRLAND_INSTANCE_SIGNATURE="$CURRENT_INSTANCE"
fi

# Auto-detect WAYLAND_DISPLAY if not set
if [ -z "$WAYLAND_DISPLAY" ]; then
  for socket in $(ls -t "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v ".lock"); do
    if [ -S "$socket" ]; then
      export WAYLAND_DISPLAY=$(basename "$socket")
      break
    fi
  done
fi

# Launch waybar directly (not using exec to keep the shell process)
# This way waybar inherits the environment variables we just set
waybar
