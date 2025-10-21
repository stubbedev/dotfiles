#!/bin/bash
# Decrease external monitor brightness by 10% using ddcutil

# Get current brightness value
current=$(ddcutil getvcp 10 | grep -oP 'current value = \K\d+')

# Calculate new brightness (min 0)
new=$((current - 10))
if [ "$new" -lt 0 ]; then
  new=0
fi

# Set new brightness
exec ddcutil setvcp 10 $new

