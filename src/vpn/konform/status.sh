#!/usr/bin/env bash

set -euo pipefail

PROVIDER_NAME="@PROVIDER_NAME@"

PID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/openconnect-${PROVIDER_NAME}.pid"

# Linux interface names cap at 15 chars; keep the same form as connect.sh.
IFACE_NAME="$(printf '%s' "oc-${PROVIDER_NAME}" | cut -c1-15)"

interface_up() {
  if [ -d "/sys/class/net/$IFACE_NAME" ]; then
    local state
    state=$(cat "/sys/class/net/$IFACE_NAME/operstate" 2>/dev/null || true)
    if [ "$state" = "up" ] || [ "$state" = "unknown" ]; then
      return 0
    fi
  fi
  return 1
}

is_running() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$pid" ]; then
      if kill -0 "$pid" 2>/dev/null; then
        if interface_up; then
          return 0
        fi
      fi

      if [ -d "/proc/$pid" ]; then
        if interface_up; then
          return 0
        fi
      fi
    fi
  fi
  return 1
}

if is_running; then
  echo "${PROVIDER_NAME} VPN: Connected"
  echo "pid: $(cat "$PID_FILE")"
else
  echo "${PROVIDER_NAME} VPN: Disconnected"
fi
