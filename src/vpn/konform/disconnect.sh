#!/usr/bin/env bash

# Disconnect from VPN

# Determine provider name from script location
SCRIPT_NAME="$(basename "$0")"
PROVIDER_NAME="${SCRIPT_NAME%-vpn-disconnect}"

VPN_NAME="${PROVIDER_NAME}-vpn"

if nmcli connection show --active | grep -q "$VPN_NAME"; then
    echo "Disconnecting from $VPN_NAME..."
    nmcli connection down "$VPN_NAME"
    echo "Disconnected."
else
    echo "VPN '$VPN_NAME' is not connected."
fi
