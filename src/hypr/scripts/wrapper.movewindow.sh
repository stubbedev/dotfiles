#!/usr/bin/env bash

DIRECTION=$1
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str')

if [ "$CURRENT_LAYOUT" = "hy3" ]; then
  hyprctl dispatch hy3:movewindow "$DIRECTION"
elif [ "$CURRENT_LAYOUT" = "scrolling" ]; then
  case "$DIRECTION" in
    l|r) hyprctl dispatch layoutmsg "swapcol $DIRECTION" ;;
    u|d) hyprctl dispatch movewindow "$DIRECTION" ;;
  esac
else
  hyprctl dispatch movewindow "$DIRECTION"
fi
