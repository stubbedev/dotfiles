#!/usr/bin/env bash
(
  uid="${UID:-$(id -u)}"
  hypr_root="/run/user/$uid/hypr"

  [ -d "$hypr_root" ] || exit 0

  target_instance=""
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && \
     [ -S "$hypr_root/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]; then
    target_instance="$HYPRLAND_INSTANCE_SIGNATURE"
  else
    newest_mtime=0
    for sock in "$hypr_root"/*/.socket.sock; do
      [ -S "$sock" ] || continue
      instance_dir="${sock%/.socket.sock}"
      instance="${instance_dir##*/}"
      mtime=$(stat -c %Y "$sock" 2>/dev/null || echo 0)
      if [ "$mtime" -gt "$newest_mtime" ]; then
        newest_mtime="$mtime"
        target_instance="$instance"
      fi
    done
  fi

  [ -n "$target_instance" ] || exit 0

  export HYPRLAND_INSTANCE_SIGNATURE="$target_instance"

  # Capture (workspace, monitor) for every monitor + the globally focused
  # workspace, reload, then restore so multi-monitor reloads don't shift
  # focus.
  before=$(@HYPRCTL@ monitors -j 2>/dev/null) || exit 0
  focused_ws=$(printf '%s' "$before" \
    | jq -r 'map(select(.focused == true))[0].activeWorkspace.id // empty')
  per_monitor=$(printf '%s' "$before" \
    | jq -r '.[] | "\(.name) \(.activeWorkspace.id)"')

  @HYPRCTL@ reload >/dev/null 2>&1 || exit 0

  # Reload re-enables eDP-1 from monitors.conf and auto-positions the
  # externals to its right; re-apply the lid-closed layout before
  # workspace restore so workspaces don't migrate back. reflow_monitors
  # disables eDP and re-packs the externals from 0,0 in one pass, so the
  # external is not left stranded at a half-screen offset. (`hyprctl
  # keyword` is rejected under the Lua config — "keyword can't work with
  # non-legacy parsers. Use eval." — so drive it through the exposed Lua
  # reflow_monitors instead.)
  if grep -qi closed /proc/acpi/button/lid/*/state 2>/dev/null; then
    @HYPRCTL@ eval "reflow_monitors(true)" >/dev/null 2>&1 || true
  fi

  # Legacy `hyprctl dispatch <name> <args>` is rejected under the Lua
  # config (it is parsed as hl.dispatch(<args>) Lua); pass a Lua
  # dispatcher expression instead. focusmonitor/workspace both map to
  # hl.dsp.focus{ monitor = ... } / hl.dsp.focus{ workspace = ... }.
  while IFS=' ' read -r mon ws; do
    [ -n "$mon" ] && [ -n "$ws" ] || continue
    @HYPRCTL@ dispatch "hl.dsp.focus({ monitor = '$mon' })" >/dev/null 2>&1 || true
    @HYPRCTL@ dispatch "hl.dsp.focus({ workspace = $ws })" >/dev/null 2>&1 || true
  done <<<"$per_monitor"

  if [ -n "$focused_ws" ]; then
    @HYPRCTL@ dispatch "hl.dsp.focus({ workspace = $focused_ws })" >/dev/null 2>&1 || true
  fi
) || true
