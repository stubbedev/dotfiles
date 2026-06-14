#!/usr/bin/env bash
# hyprsunset blue-light scheduler — the single owner of the schedule.
#
# hyprsunset (>=0.3) has NO native latitude/longitude mode — it only knows a
# fixed temperature or fixed-time profiles, so the old lat/long hyprsunset.conf
# was silently ignored (daemon stuck at its 6000K default). Drive it ourselves:
# compute the real sunrise/sunset with sunwait (offline, no network) and set the
# running daemon's temperature over its IPC socket, ramping gradually across the
# dusk/dawn transition.
#
# This process owns everything — coordinates, the day/night temperatures, and
# the decision. It writes the bar widget's state line to $state on every change
# (the widget just tails it, event-driven) and re-evaluates on SIGUSR1. The
# wayle toggle flips the override marker and signals us — it carries no schedule
# logic of its own. Runs as a restart-always systemd user service.
set -uo pipefail

# Copenhagen — keep in sync with the wayle weather module.
LAT=55.6N
LON=12.5E
DAY_TEMP=6500       # ~D65 neutral daylight: blue-light filter effectively off
NIGHT_TEMP=4500     # warm night filter
TRANSITION_SECS=300 # ramp length across a real dusk/dawn event (~5 min)
STEP_K=50           # temperature step per ramp tick

rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
marker="$rt/hyprsunset.override"
state="$rt/hyprsunset.state"
pidfile="$rt/hyprsunset-sun.pid"
sock="$rt/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.hyprsunset.sock"

send() { printf '%s' "$1" | socat - "UNIX-CONNECT:$sock" 2>/dev/null; }
cur_temp() { send temperature | tr -dc '0-9'; }

# SIGUSR1 (from the toggle) interrupts an in-progress `sunwait wait` or ramp so
# we re-evaluate immediately.
reload=0
trap 'reload=1' USR1
echo "$$" >"$pidfile"
trap 'rm -f "$pidfile"' EXIT

# The state file is the exact widget JSON line; written atomically (mv) so the
# widget's dir-watch sees one clean moved_to per change. The widget is icon-only:
# `alt` collapses to auto-vs-disabled for the icon-map (day/night both = auto);
# the tooltip keeps the full detail.
write_state() { # $1=mode(off|day|night) $2=temp
  local mode="$1" temp="$2" alt tip
  case "$mode" in
    off)   alt="off";  tip="Blue-light filter disabled (manual). Click to resume the automatic sunrise/sunset schedule." ;;
    day)   alt="auto"; tip="Auto schedule — daytime, filter off. Click to disable (force off through the night)." ;;
    night) alt="auto"; tip="Auto schedule — night, filter on at ${temp}K. Click to disable." ;;
  esac
  printf '{"alt":"%s","tooltip":"%s"}\n' "$alt" "$tip" >"$state.tmp"
  mv -f "$state.tmp" "$state"
}

# Echo "<alt> <target-temp>" for the current instant: override forces off, else
# sun position decides.
desired() {
  if [ -f "$marker" ]; then
    echo "off $DAY_TEMP"
  elif [ "$(sunwait poll "$LAT" "$LON" 2>/dev/null)" = "DAY" ]; then
    echo "day $DAY_TEMP"
  else
    echo "night $NIGHT_TEMP"
  fi
}

# Apply the current desired state. $1=1 ramps gradually, 0 snaps. A SIGUSR1
# mid-ramp abandons it and re-reads desired() so a toggle takes effect at once.
apply() {
  local ramp="$1" d alt target cur steps delay
  d="$(desired)"
  cur="$(cur_temp)"; [[ "$cur" =~ ^[0-9]+$ ]] || cur="${d#* }"
  if [ "$ramp" = 1 ]; then
    target="${d#* }"
    if [ "$cur" != "$target" ]; then
      steps=$(( (cur > target ? cur - target : target - cur) / STEP_K )); [ "$steps" -gt 0 ] || steps=1
      delay=$(( TRANSITION_SECS / steps )); [ "$delay" -gt 0 ] || delay=1
      while [ "$cur" != "$target" ] && [ "$reload" = 0 ]; do
        if [ "$cur" -lt "$target" ]; then
          cur=$(( cur + STEP_K )); [ "$cur" -gt "$target" ] && cur="$target"
        else
          cur=$(( cur - STEP_K )); [ "$cur" -lt "$target" ] && cur="$target"
        fi
        send "temperature $cur" >/dev/null
        write_state "${d% *}" "$cur"
        sleep "$delay" & wait $!
      done
    fi
  fi
  # Snap to the final target — re-read desired() in case an override toggle
  # interrupted the ramp.
  d="$(desired)"; alt="${d% *}"; target="${d#* }"
  send "temperature $target" >/dev/null
  write_state "$alt" "$target"
}

# Wait for the daemon (launched alongside us by hyprland.lua) to open its socket.
for _ in $(seq 1 60); do
  [ -S "$sock" ] && send temperature >/dev/null 2>&1 && break
  sleep 1
done

apply 0 # snap to the correct state at startup
while :; do
  reload=0
  # Block until the next sunrise OR sunset (sunwait's default waits for both),
  # interruptible by SIGUSR1. Floor with a sleep against a degenerate return.
  sunwait wait "$LAT" "$LON" & wpid=$!
  wait "$wpid" || true
  kill "$wpid" 2>/dev/null
  if [ "$reload" = 1 ]; then
    apply 0 # manual override change → snap
  else
    apply 1 # real sun event → ramp
    sleep 30
  fi
done
