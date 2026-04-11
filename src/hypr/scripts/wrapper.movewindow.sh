#!/bin/bash
# Wrapper for movewindow - works in both hy3 and scroll layouts
# Usage: wrapper.movewindow.sh <direction>

DIRECTION=$1
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | grep -o '"scroll"' | tr -d '"')

if [ "$CURRENT_LAYOUT" = "scroll" ]; then
    hyprctl dispatch movewindow $DIRECTION
else
    hyprctl dispatch hy3:movewindow $DIRECTION
fi
