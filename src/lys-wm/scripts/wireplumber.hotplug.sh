#!/usr/bin/env bash
set -euo pipefail

last=0
while IFS= read -r line; do
  [ "$line" = "HOTPLUG=1" ] || continue
  now=$(date +%s)
  [ $((now - last)) -ge 30 ] || continue
  last=$now
  systemctl --user restart wireplumber.service
done < <(udevadm monitor --property --udev --subsystem-match=drm)
