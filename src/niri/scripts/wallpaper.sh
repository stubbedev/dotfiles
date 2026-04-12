#!/usr/bin/env bash
# Start swww daemon and set wallpaper.
# swww img automatically waits for the daemon socket to be ready.
swww-daemon &
swww img ~/.stubbe/src/wallpapers/ballet.png
