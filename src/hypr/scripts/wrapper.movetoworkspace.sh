#!/usr/bin/env bash

WORKSPACE=$1
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str')
HY3_LAYOUT="hy3"
MOVE_COMMAND=$([ "$CURRENT_LAYOUT" = "$HY3_LAYOUT" ] && echo "hy3:movetoworkspace" || echo "movetoworkspace")

hyprctl dispatch "$MOVE_COMMAND" "$WORKSPACE"
