#!/usr/bin/env bash

# Check VPN status

# Determine provider name from script location or name
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# If running from source directory (status.sh), use directory name
# If running as deployed binary (provider-vpn-status), extract from name
if [[ "$SCRIPT_NAME" == "status.sh" ]]; then
    PROVIDER_NAME="$(basename "$SCRIPT_DIR")"
else
    PROVIDER_NAME="${SCRIPT_NAME%-vpn-status}"
fi

VPN_NAME="${PROVIDER_NAME}-vpn"

if nmcli connection show --active | grep -q "$VPN_NAME"; then
    echo "VPN Status: Connected"
    nmcli connection show "$VPN_NAME" | grep -E "(VPN|IP4|IP6)"
else
    echo "VPN Status: Disconnected"
fi
