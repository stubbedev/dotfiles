#!/usr/bin/env bash

# Check status of Konform VPN

VPN_NAME="konform-vpn"

if nmcli connection show --active | grep -q "$VPN_NAME"; then
  echo "VPN Status: Connected"
  nmcli connection show "$VPN_NAME" | grep -E "(VPN|IP4|IP6)"
else
  echo "VPN Status: Disconnected"
fi
