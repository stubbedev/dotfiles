#!/bin/bash

# Wait for GNOME Keyring to be unlocked and accessible
# This ensures secret-tool can retrieve credentials for mail-status.sh

MAX_ATTEMPTS=100
ATTEMPT=0

# First wait for the daemon to be running
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if systemctl --user is-active --quiet gnome-keyring-daemon.service 2>/dev/null; then
        break
    fi
    sleep 0.1
    ATTEMPT=$((ATTEMPT + 1))
done

# Now wait for the keyring to be unlocked (accessible)
# We test this by trying to search for any aerc credentials
# If the keyring is locked, secret-tool will fail or timeout
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    # Try to check if keyring is accessible by testing a simple lookup
    # timeout ensures we don't hang indefinitely if keyring is locked
    if command -v secret-tool >/dev/null 2>&1; then
        if timeout 2 secret-tool search service aerc >/dev/null 2>&1; then
            # Keyring is unlocked and accessible
            break
        fi
    else
        # secret-tool not available, just exit
        break
    fi
    sleep 0.1
    ATTEMPT=$((ATTEMPT + 1))
done

# Restart waybar so mail-status.sh can access credentials
systemctl --user restart waybar.service
