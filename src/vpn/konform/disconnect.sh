#!/usr/bin/env bash

# Disconnect from Konform VPN

VPN_NAME="konform-vpn"

if nmcli connection show --active | grep -q "$VPN_NAME"; then
  echo "Disconnecting from $VPN_NAME..."
  nmcli connection down "$VPN_NAME"
  echo "Disconnected."
else
  echo "VPN '$VPN_NAME' is not connected."
fi
