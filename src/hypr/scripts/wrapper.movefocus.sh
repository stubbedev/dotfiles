#!/usr/bin/env bash

DIRECTION=$1
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str')

if [ "$CURRENT_LAYOUT" = "hy3" ]; then
  hyprctl dispatch hy3:movefocus "$DIRECTION"
elif [ "$CURRENT_LAYOUT" = "scrolling" ]; then
  hyprctl dispatch layoutmsg "focus $DIRECTION"
else
  hyprctl dispatch movefocus "$DIRECTION"
fi
