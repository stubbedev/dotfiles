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

is_running() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$pid" ]; then
      if kill -0 "$pid" 2>/dev/null; then
        return 0
      fi

      if [ -d "/proc/$pid" ]; then
        return 0
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
