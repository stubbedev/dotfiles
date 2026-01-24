#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$SCRIPT_NAME" == "connect.sh" ]]; then
  PROVIDER_NAME="$(basename "$SCRIPT_DIR")"
else
  PROVIDER_NAME="${SCRIPT_NAME%-vpn-connect}"
fi

CONFIG_DIR="$HOME/.config/vpn/$PROVIDER_NAME"
CONFIG_FILE="$CONFIG_DIR/config"
PASSWORD_SCRIPT="$CONFIG_DIR/get-password.sh"
PID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/openconnect-${PROVIDER_NAME}.pid"
LOG_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/openconnect-${PROVIDER_NAME}.log"
OPENCONNECT_BIN="$(command -v openconnect || true)"

iface_name() {
  local raw="oc-${PROVIDER_NAME}"
  printf '%s' "${raw:0:15}"
}

IFACE_NAME="$(iface_name)"

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

is_running() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

if [ -z "$OPENCONNECT_BIN" ]; then
  echo "openconnect is not available in PATH" >&2
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found at $CONFIG_FILE" >&2
  echo "Run: cd ~/git/dotfiles/src/vpn/$PROVIDER_NAME && ./setup.sh" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

if [ -z "${VPN_GATEWAY:-}" ] || [ -z "${VPN_USERNAME:-}" ]; then
  echo "Error: Invalid configuration in $CONFIG_FILE" >&2
  exit 1
fi

if [ ! -x "$PASSWORD_SCRIPT" ]; then
  echo "Error: Password script not found at $PASSWORD_SCRIPT" >&2
  echo "Run: $SCRIPT_DIR/set-password.sh" >&2
  exit 1
fi

if is_running; then
  echo "${PROVIDER_NAME} VPN already running (pid $(cat "$PID_FILE"))"
  exit 0
fi

password=$("$PASSWORD_SCRIPT")

if [ -z "$password" ]; then
  echo "Failed to retrieve password from secret service" >&2
  exit 1
fi

printf '%s\n' "$password" | run_as_root "$OPENCONNECT_BIN" \
  --protocol=gp \
  --user "$VPN_USERNAME" \
  --passwd-on-stdin \
  --interface "$IFACE_NAME" \
  --pid-file "$PID_FILE" \
  --syslog \
  --background \
  "$VPN_GATEWAY"

echo "${PROVIDER_NAME} VPN connecting via openconnect (pid file: $PID_FILE)"
