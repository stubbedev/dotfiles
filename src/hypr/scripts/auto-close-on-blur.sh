#!/usr/bin/env bash

# Auto-close utility windows when they lose focus
# This script monitors Hyprland events and closes pavucontrol, blueman, nm-connection-editor, screen share picker when focus is lost

# List of window classes to auto-close on focus loss
AUTO_CLOSE_CLASSES=(
    "org.pulseaudio.pavucontrol"
    ".blueman-manager-wrapped"
    "nm-connection-editor"
)

# List of window titles to auto-close on focus loss (for windows without class)
AUTO_CLOSE_TITLES=(
    "Select what to share"
)

# Track previously focused window
PREV_CLASS=""
PREV_TITLE=""

# Listen to Hyprland activewindow events
socat -U - UNIX-CONNECT:"$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while read -r line; do
    # Parse activewindow event: activewindow>>CLASS,TITLE
    if [[ "$line" =~ ^activewindow\>\>([^,]*),(.*)$ ]]; then
        CURRENT_CLASS="${BASH_REMATCH[1]}"
        CURRENT_TITLE="${BASH_REMATCH[2]}"
        
        # Check if previous window was one of the auto-close windows (by class)
        for window in "${AUTO_CLOSE_CLASSES[@]}"; do
            if [[ "$PREV_CLASS" == "$window" ]] && [[ "$CURRENT_CLASS" != "$window" ]]; then
                # Previous window lost focus, close it
                hyprctl dispatch closewindow "$window"
            fi
        done
        
        # Check if previous window was one of the auto-close windows (by title)
        for title in "${AUTO_CLOSE_TITLES[@]}"; do
            if [[ "$PREV_TITLE" == "$title" ]] && [[ "$CURRENT_TITLE" != "$title" ]]; then
                # Previous window lost focus, close it by title
                hyprctl dispatch closewindow "title:$title"
            fi
        done
        
        PREV_CLASS="$CURRENT_CLASS"
        PREV_TITLE="$CURRENT_TITLE"
    fi
done
