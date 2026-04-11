#!/usr/bin/env bash

# Args: dx dy (e.g. -50 0, 50 0, 0 -50, 0 50)
DX=$1
DY=$2
CURRENT_LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str')

if [ "$CURRENT_LAYOUT" = "scrolling" ] && [ "$DX" != "0" ]; then
  # Use colresize for horizontal resizing in scrolling mode
  # Convert px delta to fractional increment (monitor width ~1920px => 50px ≈ 0.026)
  if [ "$DX" -gt 0 ]; then
    hyprctl dispatch layoutmsg "colresize +conf"
  else
    hyprctl dispatch layoutmsg "colresize -conf"
  fi
else
  hyprctl dispatch resizeactive "$DX" "$DY"
fi
