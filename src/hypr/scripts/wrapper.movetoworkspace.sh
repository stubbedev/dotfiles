#!/bin/bash
# Wrapper for movetoworkspace - works in both hy3 and scroll layouts
# Usage: wrapper.movetoworkspace.sh <workspace>

WORKSPACE=$1
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | grep -o '"scroll"' | tr -d '"')

if [ "$CURRENT_LAYOUT" = "scroll" ]; then
    hyprctl dispatch movetoworkspace $WORKSPACE
else
    hyprctl dispatch hy3:movetoworkspace $WORKSPACE
fi
