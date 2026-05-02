#!/usr/bin/env bash
# Start awww daemon and set wallpaper. awww img does NOT retry on its own,
# so we poll for the daemon's Wayland socket before dispatching the image.
set -euo pipefail

awww-daemon &

sock="/run/user/$(id -u)/${WAYLAND_DISPLAY:-wayland-1}-awww-daemon.sock"
for _ in $(seq 1 100); do
  [ -S "$sock" ] && break
  sleep 0.05
done

awww img ~/.stubbe/src/wallpapers/ballet.png
