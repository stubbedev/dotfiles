#!/usr/bin/env bash


MIN_TRIGGER=400
last_set=""

SOCK="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

is_hy3_mode() {
  local current_layout
  current_layout=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str // .set // empty' 2>/dev/null)
  [[ "${current_layout}" == "hy3" ]]
}

set_trigger() {
  if ! is_hy3_mode; then
    return
  fi
  local monitors_json width trigger

  monitors_json=$(hyprctl monitors -j 2>/dev/null) || return

  read -r width scale rl rr < <(jq -r '
    map(select(.focused == true))[0]
    | "\(.width) \(.scale) \(.reserved[0]) \(.reserved[2])"
  ' <<<"${monitors_json}")

  if [[ -z "${width}" || "${width}" == "null" ]]; then
    return
  fi

  trigger=$(awk -v w="${width}" -v s="${scale}" -v rl="${rl}" -v rr="${rr}" \
    -v m="${MIN_TRIGGER}" 'BEGIN {
    log_w = (w - rl - rr) / s;
    val = int(log_w / 3);
    if (val < m) val = m;
    printf "%d\n", val;
  }')

  if [[ "${trigger}" == "${last_set}" ]]; then
    return
  fi

  if hyprctl eval "hl.config({ plugin = { hy3 = { autotile = { trigger_width = ${trigger} } } } })" 2>/dev/null | grep -q '^ok$'; then
    last_set="${trigger}"
  fi
}

listen_events() {
  set_trigger

  while true; do
    if [[ ! -S "${SOCK}" ]]; then
      sleep 1
      continue
    fi

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
