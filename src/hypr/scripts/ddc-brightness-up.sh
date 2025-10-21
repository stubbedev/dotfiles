#!/bin/bash
# Increase external monitor brightness by 10% using ddcutil

# Get current brightness value
current=$(ddcutil getvcp 10 | grep -oP 'current value = \K\d+')

# Calculate new brightness (max 100)
new=$((current + 10))
if [ "$new" -gt 100 ]; then
  new=100
fi

# Set new brightness
exec ddcutil setvcp 10 $new
