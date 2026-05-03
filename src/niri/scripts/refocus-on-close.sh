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
# treat it as auto-focus-from-close.
#
# But only override if niri's pick is wrong. niri sometimes auto-focuses
# the actually-correct previous window (e.g. opening a window and closing
# it immediately — the prior focus is also the geometric neighbor). When
# the close-time F lands on what was stack[1] before the push, niri got it
# right and we leave it alone.
#
# Niri 26.04 does not emit WindowFocusChanged when a new window opens with
# initial focus; it only sets is_focused=true in WindowOpenedOrChanged.
# Treat that signal as an F event so newly-opened focused windows enter
# the history.
set -uo pipefail

declare -a stack=()
last_f_us=0
last_f_id=""
f_was_restore=0

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

on_focus() {
  local id="$1"
  if [ "${#stack[@]}" -ge 1 ] && [ "${stack[0]}" = "$id" ]; then
    return
  fi
  if [ "${#stack[@]}" -ge 2 ] && [ "${stack[1]}" = "$id" ]; then
    f_was_restore=1
  else
    f_was_restore=0
  fi
  push_top "$id"
  last_f_us=$(us_now)
  last_f_id="$id"
}

while IFS=' ' read -r kind id focused; do
  [ -z "${id:-}" ] && continue
  case "$kind" in
    F)
      on_focus "$id"
      ;;
    O)
      [ "${focused:-}" = "true" ] && on_focus "$id"
      ;;
    C)
      if [ "$id" != "${stack[0]:-}" ] \
         && [ "$f_was_restore" -eq 0 ] \
         && [ $(( $(us_now) - last_f_us )) -lt 50000 ] \
         && [ "${#stack[@]}" -ge 2 ]; then
        niri msg action focus-window --id "${stack[1]}" >/dev/null 2>&1 || true
      fi
      remove_id "$id"
      ;;
  esac
done < <(
  niri msg --json event-stream 2>/dev/null \
    | jq --unbuffered -rc '
        if .WindowFocusChanged then "F \(.WindowFocusChanged.id // "")"
        elif .WindowOpenedOrChanged then "O \(.WindowOpenedOrChanged.window.id) \(.WindowOpenedOrChanged.window.is_focused)"
        elif .WindowClosed then "C \(.WindowClosed.id)"
        else empty end'
)
