#!/usr/bin/env bash

# VPN Connection Script for NetworkManager
# Reads configuration from config file

# Determine provider name from script location or name
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# If running from source directory (connect.sh), use directory name
# If running as deployed binary (provider-vpn-connect), extract from name
if [[ "$SCRIPT_NAME" == "connect.sh" ]]; then
    PROVIDER_NAME="$(basename "$SCRIPT_DIR")"
else
    PROVIDER_NAME="${SCRIPT_NAME%-vpn-connect}"
fi

VPN_NAME="${PROVIDER_NAME}-vpn"
CONFIG_DIR="$HOME/.config/vpn/$PROVIDER_NAME"
CONFIG_FILE="$CONFIG_DIR/config"
PASSWORD_SCRIPT="$CONFIG_DIR/get-password.sh"

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at $CONFIG_FILE"
    echo "Please run the setup script first:"
    echo "  cd ~/git/dotfiles/src/vpn/$PROVIDER_NAME && ./setup.sh"
    exit 1
fi

source "$CONFIG_FILE"

# Validate configuration
if [ -z "$VPN_GATEWAY" ] || [ -z "$VPN_USERNAME" ]; then
    echo "Error: Invalid configuration in $CONFIG_FILE"
    echo "Please run the setup script again."
    exit 1
fi

# Check if the connection already exists
if nmcli connection show "$VPN_NAME" &> /dev/null; then
    echo "VPN connection '$VPN_NAME' already exists."
    echo "Connecting..."
    nmcli connection up "$VPN_NAME"
else
    echo "Creating VPN connection '$VPN_NAME'..."
    
    # Get password from GPG
    if [ ! -f "$PASSWORD_SCRIPT" ]; then
        echo "Error: Password script not found at $PASSWORD_SCRIPT"
        echo "Please run the set-password.sh script first."
        exit 1
    fi
    
    PASSWORD=$("$PASSWORD_SCRIPT")
    
    if [ -z "$PASSWORD" ]; then
        echo "Error: Failed to retrieve password"
        exit 1
    fi
    
    # Create the VPN connection and save to system
    nmcli connection add \
        type vpn \
        con-name "$VPN_NAME" \
        ifname -- \
        connection.permissions "" \
        vpn-type openconnect \
        -- \
        vpn.data "gateway=$VPN_GATEWAY,protocol=gp,username=$VPN_USERNAME" \
        vpn.secrets "password=$PASSWORD"
    
    echo "VPN connection created. Connecting..."
    nmcli connection up "$VPN_NAME"
    exit $?
fi

# Connection exists, just bring it up
nmcli connection up "$VPN_NAME"

