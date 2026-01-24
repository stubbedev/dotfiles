#!/usr/bin/env bash

# Event-driven hy3 autotile trigger based on focused monitor width.

MIN_TRIGGER=400
last_set=""

SOCK="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

set_trigger() {
  local monitors_json width trigger

  monitors_json=$(hyprctl monitors -j 2>/dev/null) || return

  width=$(jq -r 'map(select(.focused == true))[0].width' <<<"${monitors_json}")

  if [[ -z "${width}" || "${width}" == "null" ]]; then
    return
  fi

  trigger=$(awk -v w="${width}" -v m="${MIN_TRIGGER}" 'BEGIN {
    # Force a vertical split before a 4th column is possible
    val = (w / 4) + 1;
    if (val < m) val = m;
    printf "%d\n", int(val);
  }')

  if [[ "${trigger}" == "${last_set}" ]]; then
    return
  fi

  if hyprctl keyword plugin:hy3:autotile:trigger_width "${trigger}" >/dev/null 2>&1; then
    last_set="${trigger}"
  fi
}

listen_events() {
  # Recompute immediately, then on each relevant IPC event
  set_trigger

  while true; do
    # Wait for the event socket; reconnect if Hypr reloads
    if [[ ! -S "${SOCK}" ]]; then
      sleep 1
      continue
    fi

    # socat exits on reload/disconnect; we loop to reconnect
    socat -u UNIX-CONNECT:"${SOCK}" - 2>/dev/null | while IFS= read -r line; do
      case "${line}" in
        workspace*|focusedmon*|monitor*|createworkspace*|destroyworkspace*|movewindow*|activewindow*|focusedwindow*)
          set_trigger ;;
        *) ;; # ignore other events
      esac
    done

    sleep 1
  done
}

listen_events
