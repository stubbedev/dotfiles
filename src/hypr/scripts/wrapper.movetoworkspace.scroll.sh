#!/usr/bin/env bash

DIRECTION=$1
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str')
HY3_LAYOUT="hy3"
MOVE_COMMAND=$([ "$CURRENT_LAYOUT" = "$HY3_LAYOUT" ] && echo "hy3:movetoworkspace" || echo "movetoworkspace")

# In scroll mode, move to adjacent workspace
if [ "$DIRECTION" = "next" ]; then
  hyprctl dispatch "$MOVE_COMMAND" e+1
elif [ "$DIRECTION" = "prev" ]; then
  hyprctl dispatch "$MOVE_COMMAND" e-1
fi
