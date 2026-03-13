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
COOKIE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/openconnect-${PROVIDER_NAME}.cookie"
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

# Try to use cached cookie if available and not expired (8 hours = 28800 seconds)
cookie_valid=false
if [ -f "$COOKIE_FILE" ]; then
  cookie_age=$(($(date +%s) - $(stat -c %Y "$COOKIE_FILE" 2>/dev/null || echo 0)))
  if [ "$cookie_age" -lt 28800 ]; then
    cookie_valid=true
  else
    echo "Cached cookie expired (age: ${cookie_age}s), re-authenticating..."
    rm -f "$COOKIE_FILE"
  fi
fi

if [ "$cookie_valid" = true ]; then
  echo "Attempting connection with cached session cookie..."

  cookie=$(cat "$COOKIE_FILE")

  cookie_args=(
    "$OPENCONNECT_BIN"
    --protocol=gp
    --cookie-on-stdin
    --interface "$IFACE_NAME"
    --pid-file "$PID_FILE"
    --syslog
    --background
    "$VPN_GATEWAY"
  )

  if [ -n "$SETSID_BIN" ]; then
    if printf '%s\n' "$cookie" | run_as_root "$SETSID_BIN" "${cookie_args[@]}" 2>/dev/null; then
      echo "${PROVIDER_NAME} VPN connected using cached session (no 2FA required)"
      exit 0
    else
      echo "Cookie authentication failed, falling back to password authentication..."
      rm -f "$COOKIE_FILE"
    fi
  else
    if printf '%s\n' "$cookie" | run_as_root "${cookie_args[@]}" 2>/dev/null; then
      echo "${PROVIDER_NAME} VPN connected using cached session (no 2FA required)"
      exit 0
    else
      echo "Cookie authentication failed, falling back to password authentication..."
      rm -f "$COOKIE_FILE"
    fi
  fi
fi

# Full authentication with password (and 2FA if required)
password=$("$PASSWORD_SCRIPT")

if [ -z "$password" ]; then
  echo "Failed to retrieve password from secret service" >&2
  exit 1
fi

echo "Authenticating to retrieve session cookie..."

# First, authenticate to get the cookie
auth_output=$(mktemp)
trap 'rm -f "$auth_output"' EXIT

if printf '%s\n' "$password" | "$OPENCONNECT_BIN" \
  --protocol=gp \
  --user "$VPN_USERNAME" \
  --passwd-on-stdin \
  --authenticate \
  "$VPN_GATEWAY" >"$auth_output" 2>&1; then

  # Extract cookie from authentication output
  cookie=$(grep "^COOKIE=" "$auth_output" | cut -d= -f2- || true)

  if [ -n "$cookie" ]; then
    # Save cookie for future use
    printf '%s\n' "$cookie" >"$COOKIE_FILE"
    chmod 600 "$COOKIE_FILE"

    echo "Session cookie obtained and cached for 8 hours"

    # Now connect using the cookie
    cookie_args=(
      "$OPENCONNECT_BIN"
      --protocol=gp
      --cookie-on-stdin
      --interface "$IFACE_NAME"
      --pid-file "$PID_FILE"
      --syslog
      --background
      "$VPN_GATEWAY"
    )

    if [ -n "$SETSID_BIN" ]; then
      printf '%s\n' "$cookie" | run_as_root "$SETSID_BIN" "${cookie_args[@]}"
    else
      printf '%s\n' "$cookie" | run_as_root "${cookie_args[@]}"
    fi

    echo "${PROVIDER_NAME} VPN connecting via openconnect (pid file: $PID_FILE)"
  else
    echo "Warning: Failed to extract cookie, using direct password authentication" >&2

    # Fallback to original method
    openconnect_args=(
      "$OPENCONNECT_BIN"
      --protocol=gp
      --user "$VPN_USERNAME"
      --passwd-on-stdin
      --interface "$IFACE_NAME"
      --pid-file "$PID_FILE"
      --syslog
      --background
      "$VPN_GATEWAY"
    )

    if [ -n "$SETSID_BIN" ]; then
      printf '%s\n' "$password" | run_as_root "$SETSID_BIN" "${openconnect_args[@]}"
    else
      printf '%s\n' "$password" | run_as_root "${openconnect_args[@]}"
    fi

    echo "${PROVIDER_NAME} VPN connecting via openconnect (pid file: $PID_FILE)"
  fi
else
  echo "Authentication failed" >&2
  cat "$auth_output" >&2
  exit 1
fi
