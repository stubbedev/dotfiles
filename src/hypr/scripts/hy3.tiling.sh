#!/usr/bin/env bash

# Event-driven hy3 autotile trigger based on focused monitor width.
# Only runs when hy3 layout is active.

MIN_TRIGGER=400
last_set=""

SOCK="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

is_hy3_mode() {
  local current_layout
  current_layout=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str // .set // empty' 2>/dev/null)
  [[ "${current_layout}" == "hy3" ]]
}

set_trigger() {
  # Skip if not in hy3 mode
  if ! is_hy3_mode; then
    return
  fi
  local monitors_json width trigger

  monitors_json=$(hyprctl monitors -j 2>/dev/null) || return

  # hy3 compares trigger_width against visualBox.w which is in *logical* units
  # (post-scale, post-reserved). hyprctl monitors .width is physical pixels.
  # Use logical work-area width so the threshold matches what hy3 actually sees.
  read -r width scale rl rr < <(jq -r '
    map(select(.focused == true))[0]
    | "\(.width) \(.scale) \(.reserved[0]) \(.reserved[2])"
  ' <<<"${monitors_json}")

  if [[ -z "${width}" || "${width}" == "null" ]]; then
    return
  fi

  trigger=$(awk -v w="${width}" -v s="${scale}" -v rl="${rl}" -v rr="${rr}" \
    -v m="${MIN_TRIGGER}" 'BEGIN {
    # Logical work-area width = (physical - reserved_left - reserved_right) / scale
    log_w = (w - rl - rr) / s;
    # hy3 fires autotile when size_after_addition < trigger.
    # Want: 3rd window (size = log_w/3) NOT trigger, 4th (log_w/4) DOES trigger.
    # floor(log_w/3) satisfies both since log_w/3 is not strictly < floor(log_w/3).
    val = int(log_w / 3);
    if (val < m) val = m;
    printf "%d\n", val;
  }')

  if [[ "${trigger}" == "${last_set}" ]]; then
    return
  fi

  # `hyprctl keyword` is rejected under the Lua config ("keyword can't work
  # with non-legacy parsers. Use eval."). Set the plugin option through the
  # Lua API instead, mirroring the nested hl.config{} shape in hyprland.lua.
  # The flat "plugin:hy3:autotile:trigger_width" key is unknown to hl.config;
  # only the nested plugin.hy3.autotile.trigger_width form is accepted.
  if hyprctl eval "hl.config({ plugin = { hy3 = { autotile = { trigger_width = ${trigger} } } } })" 2>/dev/null | grep -q '^ok$'; then
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
