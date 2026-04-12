#!/usr/bin/env bash

DIRECTION=$1
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str')

if [ "$CURRENT_LAYOUT" = "hy3" ]; then
  FOCUSED=$(hyprctl activewindow -j)
  WS=$(echo "$FOCUSED" | jq '.workspace.id')
  FX=$(echo "$FOCUSED" | jq '.at[0]')
  FY=$(echo "$FOCUSED" | jq '.at[1]')
  CLIENTS=$(hyprctl clients -j | jq "[.[] | select(.workspace.id == $WS)]")

  AT_EDGE=false
  case "$DIRECTION" in
    l) MIN_X=$(echo "$CLIENTS" | jq '[.[].at[0]] | min'); [ "$FX" -le "$MIN_X" ] && AT_EDGE=true ;;
    r) MAX_X=$(echo "$CLIENTS" | jq '[.[].at[0]] | max'); [ "$FX" -ge "$MAX_X" ] && AT_EDGE=true ;;
    u) MIN_Y=$(echo "$CLIENTS" | jq '[.[].at[1]] | min'); [ "$FY" -le "$MIN_Y" ] && AT_EDGE=true ;;
    d) MAX_Y=$(echo "$CLIENTS" | jq '[.[].at[1]] | max'); [ "$FY" -ge "$MAX_Y" ] && AT_EDGE=true ;;
  esac

  [ "$AT_EDGE" = false ] && hyprctl dispatch hy3:movewindow "$DIRECTION"
elif [ "$CURRENT_LAYOUT" = "scrolling" ]; then
  case "$DIRECTION" in
    l|r) hyprctl dispatch layoutmsg "swapcol $DIRECTION" ;;
    u|d) hyprctl dispatch movewindow "$DIRECTION" ;;
  esac
else
  hyprctl dispatch movewindow "$DIRECTION"
fi
