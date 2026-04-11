#!/usr/bin/env bash

DIRECTION=$1
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str')
HY3_LAYOUT="hy3"
MOVE_COMMAND=$([ "$CURRENT_LAYOUT" = "$HY3_LAYOUT" ] && echo "hy3:movewindow" || echo "movewindow")

hyprctl dispatch "$MOVE_COMMAND" "$DIRECTION"
