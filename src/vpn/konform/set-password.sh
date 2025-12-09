#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$0")"
PROVIDER_NAME="$(basename "$SCRIPT_DIR")"

echo "Setting $PROVIDER_NAME VPN Password:"
read -srp "Password: " password
echo "$password" | gpg --symmetric --cipher-algo AES256 -o "$SCRIPT_DIR/password.gpg"
echo ""
echo "Password stored in $SCRIPT_DIR/password.gpg"
