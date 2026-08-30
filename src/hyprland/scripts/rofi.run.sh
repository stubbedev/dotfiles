#!/usr/bin/env bash
cmd="$1"
if command -v "${cmd%% *}" &>/dev/null; then
    exec bash -c "$cmd"
else
    notify-send "Rofi" "Command not found: ${cmd%% *}" -u critical
    exit 1
fi
