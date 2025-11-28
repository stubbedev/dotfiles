#!/bin/bash

SERVICE="power-profiles-daemon.service"

# Wait until the service is active
while ! systemctl is-active --quiet "$SERVICE"; do
    sleep 5
done

# Send the signal to Waybar once
if pgrep -x waybar >/dev/null; then
    pkill -SIGUSR2 waybar || true
fi

