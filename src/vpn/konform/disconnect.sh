#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$SCRIPT_NAME" == "disconnect.sh" ]]; then
  PROVIDER_NAME="$(basename "$SCRIPT_DIR")"
else
  PROVIDER_NAME="${SCRIPT_NAME%-vpn-disconnect}"
fi

PID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/openconnect-${PROVIDER_NAME}.pid"
PKILL_BIN="$(command -v pkill || true)"

run_as_root() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo -E "$@"
    return
  fi

  if command -v pkexec >/dev/null 2>&1 && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    pkexec env \
      DISPLAY="${DISPLAY:-:0}" \
      XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
      DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS}" \
      "$@"
    return
  fi

  echo "This action requires privileges; install sudo or pkexec (polkit)" >&2
  exit 1
}

if [ -z "$PKILL_BIN" ]; then
  echo "pkill is not available in PATH" >&2
  exit 1
fi

if [ -f "$PID_FILE" ]; then
  run_as_root "$PKILL_BIN" -F "$PID_FILE" || true
  rm -f "$PID_FILE"
  echo "${PROVIDER_NAME} VPN disconnected"
else
  # Fallback match
  run_as_root "$PKILL_BIN" -f "openconnect.*${PROVIDER_NAME}" || true
  echo "${PROVIDER_NAME} VPN not running"
fi
