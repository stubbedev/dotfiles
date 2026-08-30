#!/usr/bin/env bash

set -u

command -v dbus-monitor >/dev/null 2>&1 || exit 0
command -v busctl >/dev/null 2>&1 || exit 0

sess=/org/freedesktop/login1/session/auto

is_locked() {
  case "$(busctl --system get-property org.freedesktop.login1 "$sess" \
    org.freedesktop.login1.Session LockedHint 2>/dev/null)" in
  *true*) return 0 ;;
  *) return 1 ;;
  esac
}

prev=locked

dbus-monitor --system \
  "type='signal',interface='org.freedesktop.login1.Session',member='PropertiesChanged'" \
  2>/dev/null | while IFS= read -r line; do
  case "$line" in *"member=PropertiesChanged"*) ;; *) continue ;; esac

  if is_locked; then
    prev=locked
    continue
  fi

  if [ "$prev" = locked ]; then
    prev=unlocked
    sleep 0.5
    hyprctl reload >/dev/null 2>&1 || true
  fi
done
