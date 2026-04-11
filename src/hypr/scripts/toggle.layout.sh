#!/bin/bash
# Toggle between hy3 and scroll layouts in Hyprland

CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | grep -o '"scroll"' | tr -d '"')

if [ "$CURRENT_LAYOUT" = "scroll" ]; then
    hyprctl keyword general:layout hy3
    notify-send "Layout switched" "hy3" --icon=preferences-system-windows
else
    hyprctl keyword general:layout scroll
    notify-send "Layout switched" "scroll" --icon=preferences-system-windows
fi
