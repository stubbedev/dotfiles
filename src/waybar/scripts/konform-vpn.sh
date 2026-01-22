#!/usr/bin/env bash
set -euo pipefail

PROVIDER_NAME="konform"
CONFIG_DIR="$HOME/.config/vpn/$PROVIDER_NAME"
CONFIG_FILE="$CONFIG_DIR/config"
PASSWORD_SCRIPT="$CONFIG_DIR/get-password.sh"
PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/openconnect-${PROVIDER_NAME}.pid"
LOG_FILE="${XDG_RUNTIME_DIR:-/tmp}/openconnect-${PROVIDER_NAME}.log"
TERMINAL="${TERMINAL:-alacritty}"
OPENCONNECT_BIN="$(command -v openconnect || true)"
PKILL_BIN="$(command -v pkill || true)"

require_tools() {
  if [ -z "$OPENCONNECT_BIN" ]; then
    echo "openconnect is not available in PATH" >&2
    exit 1
  fi

  if [ -z "$PKILL_BIN" ]; then
    echo "pkill is not available in PATH" >&2
    exit 1
  fi
}

run_as_root() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    "$@"
    return
  fi

  if command -v pkexec >/dev/null 2>&1; then
    pkexec --disable-internal-agent "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -E "$@"
  else
    echo "This action requires privileges; install pkexec (polkit) or sudo" >&2
    exit 1
  fi
}

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
  require_tools

  if ! load_config; then
    echo "Missing VPN config at $CONFIG_FILE"
    exit 1
  fi

  if [ ! -x "$PASSWORD_SCRIPT" ]; then
    echo "Missing password script at $PASSWORD_SCRIPT"
    exit 1
  fi

  local password
  password=$("$PASSWORD_SCRIPT")

  if [ -z "$password" ]; then
    echo "Failed to read VPN password from GPG"
    exit 1
  fi

  printf '%s\n' "$password" | run_as_root "$OPENCONNECT_BIN" \
    --protocol=gp \
    --user "$VPN_USERNAME" \
    --passwd-on-stdin \
    --pid-file "$PID_FILE" \
    --logfile "$LOG_FILE" \
    --background \
    "$VPN_GATEWAY"
}

disconnect() {
  require_tools

  if [ -f "$PID_FILE" ]; then
    run_as_root "$PKILL_BIN" -F "$PID_FILE" || true
  else
    run_as_root "$PKILL_BIN" -f "openconnect.*${PROVIDER_NAME}" || true
  fi
}

toggle() {
  if is_running; then
    "$TERMINAL" -e bash -lc "${0@Q} disconnect"
  else
    "$TERMINAL" -e bash -lc "${0@Q} connect"
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
