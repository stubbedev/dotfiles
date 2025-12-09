#!/usr/bin/env bash

# Disconnect from VPN

# Determine provider name from script location or name
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# If running from source directory (disconnect.sh), use directory name
# If running as deployed binary (provider-vpn-disconnect), extract from name
if [[ "$SCRIPT_NAME" == "disconnect.sh" ]]; then
    PROVIDER_NAME="$(basename "$SCRIPT_DIR")"
else
    PROVIDER_NAME="${SCRIPT_NAME%-vpn-disconnect}"
fi

VPN_NAME="${PROVIDER_NAME}-vpn"

if nmcli connection show --active | grep -q "$VPN_NAME"; then
    echo "Disconnecting from $VPN_NAME..."
    nmcli connection down "$VPN_NAME"
    echo "Disconnected."
else
    echo "VPN '$VPN_NAME' is not connected."
fi
