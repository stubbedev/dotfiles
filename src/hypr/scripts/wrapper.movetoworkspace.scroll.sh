#!/bin/bash
# Wrapper for movetoworkspace with scroll direction - works in both layouts
# Usage: wrapper.movetoworkspace.scroll.sh <direction>
# Direction: "next" or "prev"

DIRECTION=$1
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | grep -o '"scroll"' | tr -d '"')

if [ "$CURRENT_LAYOUT" = "scroll" ]; then
    # In scroll mode, move to adjacent workspace
    if [ "$DIRECTION" = "next" ]; then
        hyprctl dispatch movetoworkspace e+1
    elif [ "$DIRECTION" = "prev" ]; then
        hyprctl dispatch movetoworkspace e-1
    fi
else
    # In hy3 mode, same behavior
    if [ "$DIRECTION" = "next" ]; then
        hyprctl dispatch hy3:movetoworkspace e+1
    elif [ "$DIRECTION" = "prev" ]; then
        hyprctl dispatch hy3:movetoworkspace e-1
    fi
fi
