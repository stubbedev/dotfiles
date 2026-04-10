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
COOKIE_FILE="$CONFIG_DIR/cookie"
PID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/openconnect-${PROVIDER_NAME}.pid"
LOG_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/openconnect-${PROVIDER_NAME}.log"
OPENCONNECT_BIN="$(command -v openconnect || true)"
SETSID_BIN="$(command -v setsid || true)"

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

  if command -v pkexec >/dev/null 2>&1 && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    pkexec "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo -E "$@"
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

load_cookie() {
  if [ ! -f "$COOKIE_FILE" ]; then
    return 1
  fi
  # shellcheck source=/dev/null
  source "$COOKIE_FILE"
  if [ -z "${VPN_COOKIE:-}" ] || [ -z "${VPN_HOST:-}" ]; then
    return 1
  fi
  return 0
}

# Authenticate via openconnect --authenticate to get a session cookie.
# Outputs COOKIE, HOST, FINGERPRINT lines which we save to COOKIE_FILE.
fetch_cookie() {
  local password="$1"
  local auth_output

  echo "Authenticating (2FA prompt expected)..." >&2

  auth_output=$(printf '%s\n' "$password" | "$OPENCONNECT_BIN" \
    --protocol=gp \
    --user "$VPN_USERNAME" \
    --passwd-on-stdin \
    --authenticate \
    "$VPN_GATEWAY" 2>/dev/null) || true

  if [ -z "$auth_output" ]; then
    echo "Authentication failed" >&2
    return 1
  fi

  # openconnect --authenticate outputs: COOKIE=...\nHOST=...\nFINGERPRINT=...
  # Remap to prefixed names to avoid polluting the environment with generic names.
  local cookie host fingerprint
  cookie=$(printf '%s\n' "$auth_output" | grep '^COOKIE=' | cut -d= -f2-)
  host=$(printf '%s\n' "$auth_output" | grep '^HOST=' | cut -d= -f2-)
  fingerprint=$(printf '%s\n' "$auth_output" | grep '^FINGERPRINT=' | cut -d= -f2-)

  if [ -z "$cookie" ] || [ -z "$host" ]; then
    echo "Failed to parse authentication response" >&2
    return 1
  fi

  mkdir -p "$CONFIG_DIR"
  printf 'VPN_COOKIE=%s\nVPN_HOST=%s\nVPN_FINGERPRINT=%s\n' \
    "$cookie" "$host" "$fingerprint" > "$COOKIE_FILE"
  chmod 600 "$COOKIE_FILE"
  return 0
}

connect_with_cookie() {
  local openconnect_args=(
    "$OPENCONNECT_BIN"
    --protocol=gp
    --user "$VPN_USERNAME"
    --cookie "$VPN_COOKIE"
    --interface "$IFACE_NAME"
    --pid-file "$PID_FILE"
    --syslog
    --background
    ${VPN_FINGERPRINT:+--servercert "$VPN_FINGERPRINT"}
    "$VPN_HOST"
  )

  if [ -n "$SETSID_BIN" ]; then
    printf '' | run_as_root "$SETSID_BIN" "${openconnect_args[@]}"
  else
    printf '' | run_as_root "${openconnect_args[@]}"
  fi
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

# Try connecting with a cached cookie first (no 2FA needed).
if load_cookie; then
  echo "Trying cached cookie..." >&2
  if connect_with_cookie 2>/dev/null; then
    echo "${PROVIDER_NAME} VPN connecting via openconnect (pid file: $PID_FILE)"
    exit 0
  fi
  echo "Cached cookie rejected, re-authenticating..." >&2
  rm -f "$COOKIE_FILE"
fi

# No valid cookie — fetch one (triggers 2FA once).
password=$("$PASSWORD_SCRIPT")
if [ -z "$password" ]; then
  echo "Failed to retrieve password from secret service" >&2
  exit 1
fi

if ! fetch_cookie "$password"; then
  exit 1
fi

load_cookie

if ! connect_with_cookie; then
  echo "Failed to connect after authentication" >&2
  rm -f "$COOKIE_FILE"
  exit 1
fi

echo "${PROVIDER_NAME} VPN connecting via openconnect (pid file: $PID_FILE)"
