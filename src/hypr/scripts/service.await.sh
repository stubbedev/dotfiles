#!/bin/bash

SERVICE="$1"

# Exit early if no service name provided
if [ -z "$SERVICE" ]; then
    exit 1
fi

# Wait until the service is active (check both user and system services)
while true; do
    if systemctl --user is-active --quiet "$SERVICE" 2>/dev/null; then
        break
    fi
    if systemctl --system is-active --quiet "$SERVICE" 2>/dev/null; then
        break
    fi
    sleep 5
done

# Send the signal to Waybar once
if pgrep -x waybar >/dev/null; then
    pkill -SIGUSR2 waybar || true
fi
