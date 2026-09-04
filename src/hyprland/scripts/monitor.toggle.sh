#!/usr/bin/env bash


apply_reload() {
  hyprctl reload >/dev/null 2>&1 || true
}

WALLPAPER="${WALLPAPER:-$HOME/.stubbe/src/wallpapers/ballet.jpg}"

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

read_lid() {
  local f line
  LID=open
  for f in /proc/acpi/button/lid/*/state; do
    [ -r "$f" ] || continue
    read -r line <"$f" || continue
    case "$line" in
    *[Cc]losed*) LID=closed ;;
    esac
    return
  done
}

apply_lid() {
  sleep 0.3

  read_lid

  if [ "$LID" = "closed" ]; then
    hyprctl eval "reflow_monitors(true)" >/dev/null 2>&1 || true
  fi
}

react() {
  apply_reload
  apply_lid
  apply_wallpaper
}

suspend_if_closed_undocked() {
  local c
  read_lid
  [ "$LID" = "closed" ] || return 0
  for c in /sys/class/drm/card*-*/status; do
    case "$c" in *eDP*) continue ;; esac
    [ "$(cat "$c" 2>/dev/null)" = "connected" ] && return 0
  done
  systemctl suspend >/dev/null 2>&1 || true
}

_last_wp_restart=0
restart_wireplumber() {
  local now
  now=$(date +%s)
  [ $((now - _last_wp_restart)) -lt 30 ] && return 0
  _last_wp_restart=$now
  systemctl --user restart wireplumber.service >/dev/null 2>&1 || true
}

poll_lid() {
  local prev
  read_lid
  prev=$LID
  # ponytail: plain 2s poll, no evdev fd. Watching /dev/input/eventN from bash
  # needs 24-byte reads; `read -N 1` gets EINVAL, never drains the queue, so the
  # fd stays readable forever and this loop spins at ~900Hz. Each turn evaluates
  # ACPI _LID -> an EC transaction -> ~3000 SCI/s on GPE 0x6E (irq/9-acpi at 85%
  # of a core). Upgrade path if 2s latency ever matters: read 24 bytes at a time.
  while sleep 2; do
    read_lid
    [ "$LID" = "$prev" ] && continue
    prev=$LID
    react

    if [ "$LID" = "closed" ]; then
      sleep 5
      suspend_if_closed_undocked
    fi
  done
}

listen_lid() {
  command -v libinput >/dev/null 2>&1 || return 0
  while true; do
    stdbuf -oL libinput debug-events --verbose 2>/dev/null \
      | grep --line-buffered -i 'lid: resume touchpad' \
      | while IFS= read -r _; do
        apply_reload
      done
    sleep 2
  done
}

listen_events() {
  local last_action=0

  react

  poll_lid &
  local poll_pid=$!
  listen_lid &
  local lid_pid=$!
  trap 'kill "$poll_pid" "$lid_pid" 2>/dev/null' EXIT INT TERM

  while IFS= read -r line; do
    [ "$line" = "HOTPLUG=1" ] || continue

    now=$(date +%s)
    if [ $((now - last_action)) -lt 1 ]; then
      continue
    fi
    react
    restart_wireplumber
    suspend_if_closed_undocked
    last_action=$(date +%s)
  done < <(udevadm monitor --property --udev --subsystem-match=drm 2>/dev/null)
}

if [ "${1:-}" = "daemon" ]; then
  listen_events
else
  react
fi
