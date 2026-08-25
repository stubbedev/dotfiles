#!/usr/bin/env bash
# "Charge to Full Now" — the button macOS puts next to Optimized Battery
# Charging. Lifts the 80% cap for the rest of this charging session; unplugging
# clears it and the cap comes straight back.
#
# Just drops a flag file: power-source-full.path is watching for it and starts
# power-source.service the moment it appears, so no sudo and no waiting for the
# next timer tick. See src/_shared/scripts/power-source.sh.
set -eu

dir=/run/battery-charge

if [ ! -d "$dir" ]; then
  echo "battery-full: $dir is missing — is power-source.timer enabled?" >&2
  exit 1
fi

touch "$dir/full-now"
echo "Charging to 100%. The 80% cap comes back when you unplug."
