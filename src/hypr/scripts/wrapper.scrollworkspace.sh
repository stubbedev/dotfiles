#!/bin/bash
# Wrapper for workspace scrolling - works in both hy3 and scroll layouts
# Usage: wrapper.scrollworkspace.sh <direction>
# Direction: "next" or "prev"

DIRECTION=$1
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | grep -o '"scroll"' | tr -d '"')

# Workspace scrolling works the same in both layouts
# but we keep this wrapper for consistency and potential future customization
if [ "$DIRECTION" = "next" ]; then
    hyprctl dispatch workspace e+1
elif [ "$DIRECTION" = "prev" ]; then
    hyprctl dispatch workspace e-1
fi
