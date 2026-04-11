#!/usr/bin/env bash

DIRECTION=$1
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str')
HY3_LAYOUT="hy3"

if [ "$CURRENT_LAYOUT" = "$HY3_LAYOUT" ]; then
  hyprctl dispatch hy3:movefocus "$DIRECTION"
else
  hyprctl dispatch movefocus "$DIRECTION"
fi
