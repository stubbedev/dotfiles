#!/usr/bin/env bash

DIRECTION=$1

if [ "$DIRECTION" = "next" ]; then
    hyprctl dispatch workspace e+1
elif [ "$DIRECTION" = "prev" ]; then
    hyprctl dispatch workspace e-1
fi
