#!/usr/bin/env bash
# Adjust external monitor brightness by 10% using ddcutil
# Usage: monitor.brightness.sh [increase|decrease]

# Check if argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 [increase|decrease]"
  exit 1
fi

# Get current brightness value
current=$(ddcutil getvcp 10 | grep -oP 'current value = \K\d+')

# Calculate new brightness based on argument
if [ "$1" = "increase" ]; then
  new=$((current + 10))
  if [ "$new" -gt 100 ]; then
    new=100
  fi
elif [ "$1" = "decrease" ]; then
  new=$((current - 10))
  if [ "$new" -lt 0 ]; then
    new=0
  fi
else
  echo "Invalid argument. Use 'increase' or 'decrease'"
  exit 1
fi

# Set new brightness
exec ddcutil setvcp 10 $new
