#!/usr/bin/env bash
set -euo pipefail

PROVIDER_NAME="konform"
CONFIG_DIR="$HOME/.config/vpn/$PROVIDER_NAME"
CONFIG_FILE="$CONFIG_DIR/config"
PASSWORD_SCRIPT="$CONFIG_DIR/get-password.sh"
PID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/openconnect-${PROVIDER_NAME}.pid"
CONNECT_SCRIPT="$HOME/.local/bin/${PROVIDER_NAME}-vpn-connect"
DISCONNECT_SCRIPT="$HOME/.local/bin/${PROVIDER_NAME}-vpn-disconnect"
TERMINAL="${TERMINAL:-alacritty}"

load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    return 1
  fi

  # shellcheck source=/dev/null
  source "$CONFIG_FILE"

  if [ -z "${VPN_GATEWAY:-}" ] || [ -z "${VPN_USERNAME:-}" ]; then
    return 1
  fi
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

status() {
  local text class tooltip

  if ! load_config; then
    text=" VPN"
    class="error"
    tooltip="VPN config missing: ${CONFIG_FILE}"
  elif is_running; then
    text=" VPN"
    class="connected"
    tooltip="${PROVIDER_NAME} VPN connected"
  else
    text=" VPN"
    class="disconnected"
    tooltip="${PROVIDER_NAME} VPN disconnected"
  fi

  printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$text" "$class" "$tooltip"
}

connect() {
  if ! load_config; then
    echo "Missing VPN config at $CONFIG_FILE" >&2
    exit 1
  fi

  if [ ! -x "$PASSWORD_SCRIPT" ]; then
    echo "Missing password script at $PASSWORD_SCRIPT" >&2
    exit 1
  fi

  # Launch via terminal to allow password/privilege prompts if needed
  "$TERMINAL" -e bash -lc "${CONNECT_SCRIPT@Q}"
}

disconnect() {
  "$TERMINAL" -e bash -lc "${DISCONNECT_SCRIPT@Q}"
}

toggle() {
  if is_running; then
    disconnect
  else
    connect
  fi
}

case "${1:-status}" in
  status)
    status
    ;;
  connect)
    connect
    ;;
  disconnect)
    disconnect
    ;;
  toggle)
    toggle
    ;;
  *)
    echo "Usage: $0 [status|connect|disconnect|toggle]" >&2
    exit 1
    ;;
esac
