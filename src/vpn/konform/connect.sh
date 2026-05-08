#!/usr/bin/env bash

set -euo pipefail

PROVIDER_NAME="@PROVIDER_NAME@"

CONFIG_DIR="$HOME/.config/vpn/$PROVIDER_NAME"
CONFIG_FILE="$CONFIG_DIR/config"
PASSWORD_FILE="$CONFIG_DIR/password"
COOKIE_FILE="$CONFIG_DIR/cookie"
PID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/openconnect-${PROVIDER_NAME}.pid"
LOG_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/openconnect-${PROVIDER_NAME}.log"
OPENCONNECT_BIN="$(command -v openconnect || true)"
SETSID_BIN="$(command -v setsid || true)"

# pkexec canonicalises the program path before the polkit rule checks
# allowedPrograms, but argv[0] passed to pkexec stays as the user-supplied
# (often symlinked) path. Our 49-openconnect.rules enforces
# args[0] === program, so the script must hand pkexec the canonical store
# path or the rule rejects on argv[0] mismatch and pkexec falls back to
# interactive auth — same root cause as power.profile.fix.sh's readlink -f.
if [ -n "$OPENCONNECT_BIN" ]; then
  OPENCONNECT_BIN="$(readlink -f "$OPENCONNECT_BIN")"
fi
if [ -n "$SETSID_BIN" ]; then
  SETSID_BIN="$(readlink -f "$SETSID_BIN")"
fi

# Linux interface names cap at 15 chars, so the iface is "oc-<provider>"
# truncated to fit. Keeping it deterministic lets status / waybar agree
# on which interface to probe.
IFACE_NAME="$(printf '%s' "oc-${PROVIDER_NAME}" | cut -c1-15)"

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
# VPN_USERGROUP defaults to "gateway" so we skip portal auth and only get one 2FA prompt
# (https://www.infradead.org/openconnect/globalprotect.html). Set VPN_USERGROUP="" in
# the config to fall back to portal auth if your deployment requires it.
fetch_cookie() {
  local password="$1"
  local auth_output
  local usergroup="${VPN_USERGROUP-gateway}"

  echo "Authenticating (2FA prompt expected)..." >&2

  auth_output=$(printf '%s\n' "$password" | "$OPENCONNECT_BIN" \
    --protocol=gp \
    --user "$VPN_USERNAME" \
    ${usergroup:+--usergroup="$usergroup"} \
    --passwd-on-stdin \
    --authenticate \
    "$VPN_GATEWAY" 2>>"$LOG_FILE") || true

  if [ -z "$auth_output" ]; then
    echo "Authentication failed" >&2
    return 1
  fi

  # openconnect --authenticate outputs shell-quoted assignments, e.g.
  #   COOKIE='auth=...'
  #   HOST='10.0.0.1'
  #   FINGERPRINT='...'
  # so we eval the matching lines to let bash strip openconnect's quoting,
  # then re-emit with %q so a later `source "$COOKIE_FILE"` round-trips safely.
  local COOKIE="" HOST="" FINGERPRINT=""
  eval "$(printf '%s\n' "$auth_output" | grep -E '^(COOKIE|HOST|FINGERPRINT)=')"

  if [ -z "$COOKIE" ] || [ -z "$HOST" ]; then
    echo "Failed to parse authentication response" >&2
    return 1
  fi

  mkdir -p "$CONFIG_DIR"
  printf 'VPN_COOKIE=%q\nVPN_HOST=%q\nVPN_FINGERPRINT=%q\n' \
    "$COOKIE" "$HOST" "$FINGERPRINT" > "$COOKIE_FILE"
  chmod 600 "$COOKIE_FILE"
  return 0
}

connect_with_cookie() {
  local usergroup="${VPN_USERGROUP-gateway}"
  local openconnect_args=(
    "$OPENCONNECT_BIN"
    --protocol=gp
    --user "$VPN_USERNAME"
    --cookie "$VPN_COOKIE"
    --interface "$IFACE_NAME"
    --pid-file "$PID_FILE"
    --syslog
    --background
  )
  # Cookie was issued via the gateway path, so the reconnect must use the same
  # path. Without this, the gateway rejects the cookie and we fall back to
  # full re-auth (extra 2FA prompt).
  if [ -n "$usergroup" ]; then
    openconnect_args+=(--usergroup="$usergroup")
  fi
  if [ -n "${VPN_FINGERPRINT:-}" ]; then
    openconnect_args+=(--servercert "$VPN_FINGERPRINT")
  fi
  openconnect_args+=("$VPN_HOST")

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
  echo "Error: VPN config not found at $CONFIG_FILE" >&2
  echo "Run: hm secret edit vpn-${PROVIDER_NAME}-config && hm switch" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

if [ -z "${VPN_GATEWAY:-}" ] || [ -z "${VPN_USERNAME:-}" ]; then
  echo "Error: $CONFIG_FILE missing VPN_GATEWAY or VPN_USERNAME" >&2
  exit 1
fi

if [ ! -f "$PASSWORD_FILE" ]; then
  echo "Error: Password file not found at $PASSWORD_FILE" >&2
  echo "Run: hm secret set vpn-${PROVIDER_NAME} && hm switch" >&2
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
password=$(<"$PASSWORD_FILE")
if [ -z "$password" ]; then
  echo "Password file $PASSWORD_FILE is empty" >&2
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
