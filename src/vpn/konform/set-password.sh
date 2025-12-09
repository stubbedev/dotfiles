#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROVIDER_NAME="$(basename "$SCRIPT_DIR")"
CONFIG_DIR="$HOME/.config/vpn/$PROVIDER_NAME"
PASSWORD_FILE="$CONFIG_DIR/password.gpg"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

echo "Setting $PROVIDER_NAME VPN Password:"
read -srp "Password: " password
echo "$password" | gpg --symmetric --cipher-algo AES256 -o "$PASSWORD_FILE"
echo ""
echo "Password stored in $PASSWORD_FILE"
