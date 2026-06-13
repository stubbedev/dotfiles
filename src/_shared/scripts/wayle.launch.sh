#!/usr/bin/env bash

# Launch wayle with proper Wayland environment detection.
# Sets HYPRLAND_INSTANCE_SIGNATURE only when an active Hyprland socket is
# found; on niri (or any other Wayland compositor) we skip Hyprland detection
# and proceed — wayle's hyprland modules just stay inactive there.
#
# Fork-minimal: globs instead of ls|grep, ${var%/*}/${var##*/} instead of
# dirname/basename, a single id -u. flock and sleep are the only forks left —
# they are the liveness primitive and the retry backoff, not avoidable.

shopt -s nullglob

uid=$(id -u)
runtime="${XDG_RUNTIME_DIR:-/run/user/$uid}"

CURRENT_INSTANCE=""
attempt=0

if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
  if [ -S "/run/user/$uid/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]; then
    CURRENT_INSTANCE="$HYPRLAND_INSTANCE_SIGNATURE"
  fi
fi

# Only scan for a Hyprland instance if we look like a Hyprland session;
# otherwise jump straight to launching wayle.
if [ -z "$CURRENT_INSTANCE" ] && [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ]; then
  while [ $attempt -lt 50 ] && [ -z "$CURRENT_INSTANCE" ]; do
    for lockfile in "/run/user/$uid/hypr/"*/hyprland.lock; do
      instance_dir="${lockfile%/*}"
      if [ -S "$instance_dir/.socket.sock" ]; then
        CURRENT_INSTANCE="${instance_dir##*/}"
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
  [ -S "$runtime/$display" ] || return 1
  [ -e "$runtime/$display.lock" ] || return 1
  ! flock -n -x "$runtime/$display.lock" true 2>/dev/null
}

# Auto-detect WAYLAND_DISPLAY if not set or if the socket is stale.
if [ -n "$WAYLAND_DISPLAY" ] && _wayland_live "$WAYLAND_DISPLAY"; then
  :
else
  unset WAYLAND_DISPLAY
  attempt=0
  while [ $attempt -lt 50 ] && [ -z "$WAYLAND_DISPLAY" ]; do
    for socket in "$runtime"/wayland-[0-9]*; do
      # Skip lock/aux files — real sockets are wayland-<digits>, no dot.
      case "$socket" in *.*) continue ;; esac
      candidate="${socket##*/}"
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

export GDK_BACKEND=wayland

# Replace this shell with the desktop shell (no lingering wrapper process).
exec @WAYLE@ shell
