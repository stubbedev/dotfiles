#!/usr/bin/env bash

# Re-apply the wallpaper to every monitor on DRM hotplug (niri parity with
# the wallpaper branch of hypr/scripts/monitor.toggle.sh).
#
# wayle's `wallpaper set` (without --monitor) only paints the outputs live
# the moment it runs — wayle-launch applies it once at startup, so a monitor
# brought up later by a dock comes up blank. niri rebinds its own outputs on
# hotplug reliably (no layout reload needed, unlike Hyprland), but nothing
# re-touches wayle's wallpaper layer, so we do it here.
#
# Why udev, not niri's event-stream: niri's IPC event-stream surfaces
# window/workspace events, not DRM connector changes. udev sees the
# kernel-level HOTPLUG=1 uevent for every connector change with no compositor
# in the path — the same canonical signal monitor.toggle.sh uses on Hyprland.
#
# WALLPAPER comes from the session env (modules/home/session-variables.nix,
# sourced from constants.paths.wallpaper — the single source of truth shared
# with wayle-launch). Fall back to the literal path for a bare shell that
# never imported the session vars.
set -uo pipefail

WALLPAPER="${WALLPAPER:-$HOME/.stubbe/src/wallpapers/ballet.jpg}"

# Re-issue the set, retrying briefly in the background (~3s) without blocking
# the udev loop: the new output may not be registered in wayle the instant
# the kernel emits the uevent.
apply_wallpaper() {
  command -v wayle >/dev/null 2>&1 || return 0
  (
    n=0
    while [ $n -lt 12 ]; do
      if wayle wallpaper set "$WALLPAPER" --fit fill >/dev/null 2>&1; then
        break
      fi
      n=$((n + 1))
      sleep 0.25
    done
  ) &
}

last_action=0

# Initial sync so the wallpaper covers whatever is already connected after a
# niri (re)start, even if wayle-launch raced the outputs.
apply_wallpaper

# udevadm emits one HOTPLUG=1 property line per DRM hotplug uevent. The 1s
# debounce collapses the short burst the kernel emits when multiple
# connectors flap together (common on dock plug/unplug).
while IFS= read -r line; do
  [ "$line" = "HOTPLUG=1" ] || continue

  now=$(date +%s)
  if [ $((now - last_action)) -lt 1 ]; then
    continue
  fi
  apply_wallpaper
  last_action=$(date +%s)
done < <(udevadm monitor --property --udev --subsystem-match=drm 2>/dev/null)
