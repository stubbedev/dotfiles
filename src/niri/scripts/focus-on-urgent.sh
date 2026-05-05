#!/usr/bin/env bash
# Focus a window when it becomes urgent. Triggered e.g. by xdg-activation
# when a browser opens a link routed to an existing window — niri marks
# the target window urgent, and we promote that to a focus switch.
set -uo pipefail

niri msg --json event-stream 2>/dev/null \
  | jq --unbuffered -rc '
      if .WindowUrgencyChanged.urgent == true then .WindowUrgencyChanged.id
      elif .WindowOpenedOrChanged.window.is_urgent == true then .WindowOpenedOrChanged.window.id
      else empty end' \
  | while read -r id; do
      [ -n "$id" ] || continue
      niri msg action focus-window --id "$id" >/dev/null 2>&1 || true
    done
