#!/bin/bash

# Wait for GNOME Keyring to be unlocked and accessible
# This ensures secret-tool can retrieve credentials for mail-status.sh
# 
# This script is triggered by waybar.service, not by session startup,
# so it won't block login if it takes time or fails

MAX_WAIT_DAEMON=30  # 3 seconds max to wait for daemon
MAX_WAIT_UNLOCK=10  # 1 second max to wait for unlock
ATTEMPT=0

# First wait for the daemon to be running (quick check)
while [ $ATTEMPT -lt $MAX_WAIT_DAEMON ]; do
    if systemctl --user is-active --quiet gnome-keyring-daemon.service 2>/dev/null; then
        break
    fi
    sleep 0.1
    ATTEMPT=$((ATTEMPT + 1))
done

# Exit early if daemon isn't running
if [ $ATTEMPT -eq $MAX_WAIT_DAEMON ]; then
    echo "gnome-keyring-daemon not running, skipping waybar restart" >&2
    exit 0
fi

# Quick check if keyring is unlocked (don't wait long)
ATTEMPT=0
UNLOCKED=false

while [ $ATTEMPT -lt $MAX_WAIT_UNLOCK ]; do
    if command -v secret-tool >/dev/null 2>&1; then
        # Use very short timeout to avoid blocking
        if timeout 0.5 secret-tool search service aerc >/dev/null 2>&1; then
            UNLOCKED=true
            break
        fi
    else
        # secret-tool not available, just exit gracefully
        echo "secret-tool not available, skipping waybar restart" >&2
        exit 0
    fi
    sleep 0.1
    ATTEMPT=$((ATTEMPT + 1))
done

# Only restart waybar if keyring was successfully unlocked
if [ "$UNLOCKED" = true ]; then
    # Restart waybar so mail-status.sh can access credentials
    # Use --no-block to avoid hanging
    systemctl --user restart --no-block waybar.service
else
    # Keyring is locked, exit gracefully
    # Waybar will handle locked keyring on its own
    echo "Keyring still locked, skipping waybar restart" >&2
    exit 0
fi
