#!/usr/bin/env bash
set -euo pipefail

PROVIDER_NAME="konform"
CONFIG_DIR="$HOME/.config/vpn/$PROVIDER_NAME"
CONFIG_FILE="$CONFIG_DIR/config"
PASSWORD_FILE="$CONFIG_DIR/password"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PID_FILE="$RUNTIME_DIR/openconnect-${PROVIDER_NAME}.pid"
CONNECTING_FILE="$RUNTIME_DIR/openconnect-${PROVIDER_NAME}.connecting"
LOG_FILE="$RUNTIME_DIR/openconnect-${PROVIDER_NAME}-waybar.log"
CONNECT_SCRIPT="$HOME/.local/bin/${PROVIDER_NAME}-vpn-connect"
DISCONNECT_SCRIPT="$HOME/.local/bin/${PROVIDER_NAME}-vpn-disconnect"
CONNECT_TIMEOUT=30

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

# Returns 0 if a connect attempt is currently in flight (and within the timeout window).
# On timeout, kills the wrapper process group and triggers disconnect to clean up any
# half-started openconnect daemon, then returns 1.
connecting_active() {
  [ -f "$CONNECTING_FILE" ] || return 1

  local PID="" START=0
  # shellcheck source=/dev/null
  source "$CONNECTING_FILE" 2>/dev/null || {
    rm -f "$CONNECTING_FILE"
    return 1
  }

  if [ -z "$PID" ] || [ "$START" -eq 0 ]; then
    rm -f "$CONNECTING_FILE"
    return 1
  fi

  # Stale marker (process gone, trap didn't run for some reason)
  if ! kill -0 "$PID" 2>/dev/null; then
    rm -f "$CONNECTING_FILE"
    return 1
  fi

  local now age
  now=$(date +%s)
  age=$(( now - START ))

  if (( age >= CONNECT_TIMEOUT )); then
    kill -TERM -- "-$PID" 2>/dev/null || kill -TERM "$PID" 2>/dev/null || true
    rm -f "$CONNECTING_FILE"
    if [ -f "$PID_FILE" ]; then
      setsid "$DISCONNECT_SCRIPT" </dev/null >>"$LOG_FILE" 2>&1 &
      disown
    fi
    return 1
  fi

  return 0
}

status() {
  local text class tooltip

  if ! load_config; then
    text="󰫜"
    class="error"
    tooltip="VPN config missing: ${CONFIG_FILE}"
  elif is_running; then
    text="󰦝"
    class="connected"
    tooltip="${PROVIDER_NAME} VPN connected"
    rm -f "$CONNECTING_FILE"
  elif connecting_active; then
    text="󱦛"
    class="connecting"
    tooltip="${PROVIDER_NAME} VPN connecting..."
  else
    text="󱦚"
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

  if [ ! -f "$PASSWORD_FILE" ]; then
    echo "Missing password file at $PASSWORD_FILE" >&2
    exit 1
  fi

  rm -f "$CONNECTING_FILE"

  local now
  now=$(date +%s)

  # Spawn the connect script in its own session so we can kill the whole group
  # on timeout. The wrapper writes a marker file with its PID + start timestamp
  # and clears it on exit (success, failure, or SIGTERM).
  setsid bash -c '
    marker="$1"
    start="$2"
    script="$3"
    trap "rm -f \"$marker\"" EXIT
    printf "PID=%s\nSTART=%s\n" "$$" "$start" > "$marker"
    exec "$script"
  ' _ "$CONNECTING_FILE" "$now" "$CONNECT_SCRIPT" </dev/null >>"$LOG_FILE" 2>&1 &
  disown
}

disconnect() {
  # Cancel any in-flight connect attempt
  if [ -f "$CONNECTING_FILE" ]; then
    local PID="" START=0
    # shellcheck source=/dev/null
    source "$CONNECTING_FILE" 2>/dev/null || true
    if [ -n "$PID" ]; then
      kill -TERM -- "-$PID" 2>/dev/null || kill -TERM "$PID" 2>/dev/null || true
    fi
    rm -f "$CONNECTING_FILE"
  fi

  setsid "$DISCONNECT_SCRIPT" </dev/null >>"$LOG_FILE" 2>&1 &
  disown
}

toggle() {
  if is_running; then
    disconnect
  elif connecting_active; then
    # User clicked while connecting — treat as cancel
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
