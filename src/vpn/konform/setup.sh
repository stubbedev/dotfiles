#!/usr/bin/env bash

# One-time setup script for Konform VPN
# This creates the config file with VPN details

CONFIG_FILE="$(dirname "$0")/config"

echo "=== Konform VPN Setup ==="
echo ""

# Prompt for VPN details
read -p "VPN Gateway [vpn.konform.com]: " gateway
gateway=${gateway:-vpn.konform.com}

read -p "Username: " username

echo ""
echo "Creating configuration file..."

# Create config file
cat >"$CONFIG_FILE" <<EOF
# Konform VPN Configuration
# Generated on $(date)

VPN_GATEWAY="$gateway"
VPN_USERNAME="$username"
EOF

chmod 600 "$CONFIG_FILE"

echo "Configuration saved to: $CONFIG_FILE"
echo ""
echo "Next step: Set your password by running:"
echo "  $(dirname "$0")/set-password.sh"
