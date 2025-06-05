#!/bin/bash

SERVICE="power-profiles-daemon.service"

# Wait until the service is active
while ! systemctl is-active --quiet "$SERVICE"; do
    sleep 5
done

# Send the signal to Waybar once
pkill waybar && hyprctl dispatch exec waybar

