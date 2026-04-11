#!/bin/bash
# Wrapper for killactive - works in both hy3 and scroll layouts

CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | grep -o '"scroll"' | tr -d '"')

if [ "$CURRENT_LAYOUT" = "scroll" ]; then
    hyprctl dispatch killactive
else
    hyprctl dispatch hy3:killactive
fi
