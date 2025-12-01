#!/bin/bash

SERVICE="$1"

# Exit early if no service name provided
if [ -z "$SERVICE" ]; then
    exit 1
fi

# Wait until the service is active
while ! systemctl is-active --quiet "$SERVICE"; do
    sleep 5
done

# Send the signal to Waybar once
if pgrep -x waybar >/dev/null; then
    pkill -SIGUSR2 waybar || true
fi
