#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$SCRIPT_NAME" == "status.sh" ]]; then
  PROVIDER_NAME="$(basename "$SCRIPT_DIR")"
else
  PROVIDER_NAME="${SCRIPT_NAME%-vpn-status}"
fi

PID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/openconnect-${PROVIDER_NAME}.pid"

iface_name() {
  local raw="oc-${PROVIDER_NAME}"
  printf '%s' "${raw:0:15}"
}

IFACE_NAME="$(iface_name)"

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
