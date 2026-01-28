#!/bin/bash

# Launch waybar using hyprctl dispatch exec
# This ensures waybar is launched within the Hyprland context

# Kill any existing waybar instances first
pkill -x waybar || true

# Give it a moment to fully terminate
sleep 0.5

if command -v hyprctl >/dev/null 2>&1; then
    hyprctl dispatch exec waybar
else
    # Fallback if hyprctl is not available
    waybar
fi
