#!/usr/bin/env bash

SCROLLING_LAYOUT="scrolling"
HY3_LAYOUT="hy3"
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str')

if [ "$CURRENT_LAYOUT" = "$SCROLLING_LAYOUT" ]; then
  hyprctl keyword animations:enabled false
  hyprctl keyword general:layout $HY3_LAYOUT
  notify-send "Window Layout" "$HY3_LAYOUT" --icon=preferences-system-windows
else
  hyprctl keyword animations:enabled true
  hyprctl keyword general:layout $SCROLLING_LAYOUT
  notify-send "Window Layout" "$SCROLLING_LAYOUT" --icon=preferences-system-windows
fi
