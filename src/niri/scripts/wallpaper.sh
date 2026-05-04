#!/usr/bin/env bash
# Start awww daemon, apply wallpaper, then re-apply whenever the niri output
# set changes — awww-daemon detects new outputs but leaves them blank until
# an explicit `awww img` is dispatched.
set -euo pipefail

WALLPAPER="$HOME/.stubbe/src/wallpapers/ballet.jpg"

awww-daemon &

sock="/run/user/$(id -u)/${WAYLAND_DISPLAY:-wayland-1}-awww-daemon.sock"
for _ in $(seq 1 100); do
  [ -S "$sock" ] && break
  sleep 0.05
done

apply() { awww img "$WALLPAPER" >/dev/null 2>&1 || true; }
apply

# Niri has no explicit OutputAdded/Removed event, but every output change
# emits WorkspacesChanged with the new output set — diff that to detect
# hotplugs without re-applying on every focus/window event.
last=""
niri msg --json event-stream 2>/dev/null \
  | jq --unbuffered -r 'select(.WorkspacesChanged) | [.WorkspacesChanged.workspaces[].output] | unique | join(",")' \
  | while IFS= read -r outputs; do
      if [ "$outputs" != "$last" ]; then
        last="$outputs"
        apply
      fi
    done
