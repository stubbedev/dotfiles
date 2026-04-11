#!/usr/bin/env bash

CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str')
HY3_LAYOUT="hy3"

if [ "$CURRENT_LAYOUT" = "$HY3_LAYOUT" ]; then
  hyprctl dispatch hy3:killactive
else
  hyprctl dispatch killactive
fi
