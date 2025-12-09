#!/usr/bin/env bash

# One-time setup script for VPN
# This creates the config file with VPN details

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROVIDER_NAME="$(basename "$SCRIPT_DIR")"
CONFIG_DIR="$HOME/.config/vpn/$PROVIDER_NAME"
CONFIG_FILE="$CONFIG_DIR/config"

echo "=== $PROVIDER_NAME VPN Setup ==="
echo ""

# Prompt for VPN details
read -p "VPN Gateway: " gateway

if [ -z "$gateway" ]; then
    echo "Error: VPN Gateway is required"
    exit 1
fi

read -p "Username: " username

if [ -z "$username" ]; then
    echo "Error: Username is required"
    exit 1
fi

echo ""
echo "Creating configuration directory and file..."

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Create config file
cat > "$CONFIG_FILE" << EOF
# $PROVIDER_NAME VPN Configuration
# Generated on $(date)

VPN_GATEWAY="$gateway"
VPN_USERNAME="$username"
EOF

chmod 600 "$CONFIG_FILE"

echo "Configuration saved to: $CONFIG_FILE"
echo ""
echo "Next step: Set your password by running:"
echo "  $SCRIPT_DIR/set-password.sh"

