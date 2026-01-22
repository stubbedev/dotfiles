#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROVIDER_NAME="$(basename "$SCRIPT_DIR")"
CONFIG_DIR="$HOME/.config/vpn/$PROVIDER_NAME"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

echo "Setting $PROVIDER_NAME VPN Password:"
read -srp "Password: " password
printf '%s' "$password" | secret-tool store --label="$PROVIDER_NAME VPN" service vpn provider "$PROVIDER_NAME"
unset password
echo ""
echo "Password stored in GNOME Keyring"
