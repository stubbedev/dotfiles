#!/usr/bin/env bash
# Swayidle configuration
# Converted from Hyprland hypridle.conf

swayidle -w \
    timeout 300 'loginctl lock-session' \
    before-sleep 'loginctl lock-session'