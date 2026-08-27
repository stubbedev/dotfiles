#!/usr/bin/env bash
# Wrapper for rofi run mode — only executes if the command exists in PATH.
cmd="$1"
if command -v "${cmd%% *}" &>/dev/null; then
    exec bash -c "$cmd"
else
    notify-send "Rofi" "Command not found: ${cmd%% *}" -u critical
    exit 1
fi
