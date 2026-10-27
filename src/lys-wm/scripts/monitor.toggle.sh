#!/usr/bin/env bash


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

# Both Mains and USB: a USB-C-only charger may never register as Mains.
on_ac() {
  local ps
  for ps in /sys/class/power_supply/*; do
    [ -r "$ps/type" ] && [ -r "$ps/online" ] || continue
    case "$(cat "$ps/type")" in
    Mains | USB) ;;
    *) continue ;;
    esac
    [ "$(cat "$ps/online")" = "1" ] && return 0
  done
  return 1
}

suspend_if_closed_undocked() {
  local c
  read_lid
  [ "$LID" = "closed" ] || return 0
  for c in /sys/class/drm/card*-*/status; do
    case "$c" in *eDP*) continue ;; esac
    [ "$(cat "$c" 2>/dev/null)" = "connected" ] && return 0
  done
  on_ac && return 0
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

    if [ "$LID" = "closed" ]; then
      sleep 5
      suspend_if_closed_undocked
    fi
  done
}

watch_power() {
  udevadm monitor --property --udev --subsystem-match=power_supply 2>/dev/null \
    | grep --line-buffered '^UDEV .*power_supply' \
    | while IFS= read -r _; do
      sleep 2
      suspend_if_closed_undocked
    done
}

listen_events() {
  local last_action=0

  poll_lid &
  local poll_pid=$!
  watch_power &
  local power_pid=$!
  trap 'kill "$poll_pid" "$power_pid" 2>/dev/null' EXIT INT TERM

  while IFS= read -r line; do
    [ "$line" = "HOTPLUG=1" ] || continue

    now=$(date +%s)
    if [ $((now - last_action)) -lt 1 ]; then
      continue
    fi
    restart_wireplumber
    suspend_if_closed_undocked
    last_action=$(date +%s)
  done < <(udevadm monitor --property --udev --subsystem-match=drm 2>/dev/null)
}

listen_events
