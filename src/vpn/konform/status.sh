#!/usr/bin/env bash

# Check VPN status

# Determine provider name from script location
SCRIPT_NAME="$(basename "$0")"
PROVIDER_NAME="${SCRIPT_NAME%-vpn-status}"

VPN_NAME="${PROVIDER_NAME}-vpn"

if nmcli connection show --active | grep -q "$VPN_NAME"; then
    echo "VPN Status: Connected"
    nmcli connection show "$VPN_NAME" | grep -E "(VPN|IP4|IP6)"
else
    echo "VPN Status: Disconnected"
fi
