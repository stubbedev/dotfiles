#!/usr/bin/env bash
# Refocus on close: when the focused window closes, niri auto-focuses its
# geometric neighbor (column to the right). Override with the actually-
# previously-focused window from our own focus history.
#
# Niri's focus-window-previous only toggles between two windows and the
# close sequence (auto-focus → WindowClosed) makes that toggle land on the
# wrong entry — for two firefox windows it sends focus to the program
# focused before firefox instead of the other firefox window.
#
# Detection: when a close causes the focus shift, niri emits
# WindowFocusChanged then WindowClosed back-to-back in the same tick
# (sub-ms apart). If a C arrives within 50ms of an F with a different id,
# treat it as auto-focus-from-close and focus stack[1].
set -uo pipefail

declare -a stack=()
last_f_us=0
last_f_id=""

push_top() {
  local id="$1" e new=()
  new+=("$id")
  for e in "${stack[@]}"; do
    [ "$e" = "$id" ] || new+=("$e")
  done
  stack=("${new[@]}")
}

remove_id() {
  local id="$1" e new=()
  for e in "${stack[@]}"; do
    [ "$e" = "$id" ] || new+=("$e")
  done
  stack=("${new[@]}")
}

us_now() { printf '%s' "${EPOCHREALTIME/./}"; }

while IFS=' ' read -r kind id; do
  [ -z "${id:-}" ] && continue
  case "$kind" in
    F)
      last_f_us=$(us_now)
      last_f_id="$id"
      push_top "$id"
      ;;
    C)
      remove_id "$id"
      if [ "$id" != "$last_f_id" ] \
         && [ $(( $(us_now) - last_f_us )) -lt 50000 ] \
         && [ "${#stack[@]}" -ge 2 ]; then
        niri msg action focus-window --id "${stack[1]}" >/dev/null 2>&1 || true
      fi
      ;;
  esac
done < <(
  niri msg --json event-stream 2>/dev/null \
    | jq --unbuffered -rc '
        if .WindowFocusChanged then "F \(.WindowFocusChanged.id // "")"
        elif .WindowClosed then "C \(.WindowClosed.id)"
        else empty end'
)
