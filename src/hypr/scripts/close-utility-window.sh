#!/usr/bin/env bash

# Close utility windows (pavucontrol, blueman, nm-connection-editor) when Escape or Q is pressed
# Get the focused window's class
FOCUSED_CLASS=$(hyprctl activewindow -j | jq -r '.class')

# List of utility window classes that should be closeable with Escape/Q
UTILITY_WINDOWS=(
    "org.pulseaudio.pavucontrol"
    ".blueman-manager-wrapped"
    "nm-connection-editor"
)

# Check if focused window is one of the utility windows
for window in "${UTILITY_WINDOWS[@]}"; do
    if [[ "$FOCUSED_CLASS" == "$window" ]]; then
        hyprctl dispatch killactive
        exit 0
    fi
done

# Not a utility window, do nothing
exit 0
