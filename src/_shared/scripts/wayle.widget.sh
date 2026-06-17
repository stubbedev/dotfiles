#!/usr/bin/env bash
# Reshape waybar-style status scripts' JSON for wayle's custom modules: drop
# the nerd-font glyph from `text` (wayle shows its own icon-name instead) and
# surface a clean value. tooltip/class preserved for hover + styling.
#
# Every mode is event-driven (wayle `mode = "watch"`): emit the current line,
# then re-emit on each real state change — no polling. Sources:
#   mail        inotify on the notmuch maildir (new/cur)
#   treeman     `treeman logs tail --follow` event stream
#   vpn-watch   inotify on the openconnect pid/connecting markers
#   powerprofile  power-profiles-daemon D-Bus ActiveProfile signal
set -uo pipefail

# Emit one reshaped line for a poll-style status cmd: JSON when it has output,
# else an empty line (hide-if-empty collapses it). Never exits the watcher.
emit_line() {
  local filt="$1" out
  shift
  out="$("$@" 2>/dev/null)" || { echo; return; }
  [ -n "$out" ] || { echo; return; }
  printf '%s\n' "$(printf '%s' "$out" | jq -c "$filt" 2>/dev/null)"
}

# Single tri-state line: map vpn-konform-bar's `class` to an `alt` key that
# drives the vpn module's icon-map + color-map (on / connecting / off), tooltip
# preserved. Replaces the old three-module hide-if-empty split — one module now
# swaps icon + color by state. ("error" → off, matching the old behaviour.)
vpn_line() {
  emit_line '{alt: (if .class == "connected" then "on" elif .class == "connecting" then "connecting" else "off" end), tooltip}' vpn-konform-bar status
}

mail_line() { emit_line 'if (.text | test("[0-9]")) then (.text |= gsub("[^0-9]";"")) else empty end' mail-status; }
# Pass treeman's text through unchanged: its waybar text is a compact
# per-bucket "{glyph} {count}" line (configured via status.formats.icon in
# ~/.config/treeman/config.yaml), so the bucket glyphs ARE the content. The
# treeman custom module drops its own icon-name (config.toml) to avoid a
# duplicate leading icon.
treeman_line() { emit_line '.' treeman-status; }

rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

case "${1:-}" in
  # New mail / read state changes land in the maildir's new/ and cur/ dirs.
  # Single-shot inotify + a short settle coalesces an mbsync burst into one
  # notmuch query instead of one per delivered file.
  mail-watch)
    maildir="$(notmuch config get database.path 2>/dev/null || true)"
    mail_line
    [ -n "$maildir" ] || exit 0
    while inotifywait -q -r -e create,moved_to,moved_from,delete --include '/(new|cur)/' "$maildir" >/dev/null 2>&1; do
      sleep 0.5
      mail_line
    done
    ;;

  # treeman daemon streams lifecycle events; re-render status on each.
  # --all: global (status aggregates every repo; without it `logs tail`
  # auto-filters to the cwd, which for a bar widget is wrong/empty).
  # --since 1s: skip the default 50-event history replay. --json: machine form.
  treeman-watch)
    treeman_line
    treeman logs tail --follow --all --json --since 1s 2>/dev/null |
      while IFS= read -r _; do treeman_line; done
    ;;

  # VPN state changes from two sources, both event-driven:
  #   - the .connecting marker (inotify) → the in-flight "connecting" state
  #   - the oc-konform tunnel interface up/down (ip monitor) → connected /
  #     disconnected. The interface is the ground truth: on disconnect the
  #     openconnect PROCESS dies (no reliable marker-file event — disconnect.sh
  #     can leave the pid file behind), but the kernel always reports the link
  #     going down, so this catches the disconnect the file-watch missed.
  vpn-watch)
    vpn_line
    {
      inotifywait -q -m -e create,delete,close_write,moved_to,moved_from --format '%f' "$rt" 2>/dev/null &
      ip monitor link 2>/dev/null &
      wait
    } | while IFS= read -r line; do
      case "$line" in
        openconnect-*.pid | openconnect-*.connecting | *oc-konform*) vpn_line ;;
      esac
    done
    ;;

  # Power profile as one module: emit the active profile as `alt`, which drives
  # the module's icon-map + color-map (power-saver / balanced / performance).
  # Re-emits on the daemon's D-Bus ActiveProfile signal.
  powerprofile-watch)
    pp() {
      local cur
      cur="$(powerprofilesctl get 2>/dev/null)"
      [ -n "$cur" ] && printf '{"alt":"%s"}\n' "$cur" || echo
    }
    pp
    dbus-monitor --system "type='signal',path=/net/hadess/PowerProfiles,interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'" 2>/dev/null |
      while IFS= read -r line; do
        case "$line" in *ActiveProfile*) pp ;; esac
      done
    ;;

  # Submap indicator: the hl Lua submap (SUPER+R resize_mode) writes a tmpfs
  # marker on enter and removes it on exit (see src/hypr/hyprland.lua), since
  # it isn't a native Hyprland submap the bar could observe. Show the mode name
  # while the marker exists, empty (hidden) otherwise.
  submap-watch)
    marker="$rt/wayle-submap"
    emit_submap() {
      if [ -f "$marker" ]; then printf '{"text":"%s"}\n' "$(cat "$marker" 2>/dev/null)"; else echo; fi
    }
    emit_submap
    inotifywait -q -m -e create,delete,close_write,moved_to,moved_from --format '%f' "$rt" 2>/dev/null |
      while IFS= read -r f; do
        case "$f" in wayle-submap) emit_submap ;; esac
      done
    ;;

  # hyprsunset state for the bar. hyprsunset.sun.sh owns the schedule and writes
  # the widget JSON line to $state on every change (day/night/override + live
  # temperature during a ramp); we just tail it — fully event-driven, the dir
  # watch fires on the scheduler's atomic mv. icon-map keys on the `alt`
  # (day=sun, night=moon, off=manual-override).
  hyprsunset-watch)
    state="$rt/hyprsunset.state"
    emit() { if [ -f "$state" ]; then cat "$state"; else echo; fi; }
    emit
    inotifywait -q -m -e create,close_write,moved_to --format '%f' "$rt" 2>/dev/null |
      while IFS= read -r f; do
        case "$f" in hyprsunset.state) emit ;; esac
      done
    ;;

  # Click handler: flip the manual-override marker (force filter off past sunset
  # / hand back to auto) and poke the scheduler, which owns all the schedule
  # logic and repaints $state. No temperatures or coords live here.
  hyprsunset-toggle)
    marker="$rt/hyprsunset.override"
    if [ -f "$marker" ]; then rm -f "$marker"; else : >"$marker"; fi
    pidfile="$rt/hyprsunset-sun.pid"
    [ -f "$pidfile" ] && kill -USR1 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null
    ;;

  # Keyboard-layout toast. xkb `grp:toggle` switches the layout internally
  # (no compositor keybind to hook), so listen to each compositor's event
  # stream and fire a transient OSD toast on every switch — the bar's
  # keyboard-input module already shows the persistent state. $2 = niri|hypr.
  kb-toast)
    case "${2:-}" in
      niri)
        # event-stream emits KeyboardLayoutsChanged (the layout names) once,
        # then KeyboardLayoutSwitched {idx} on each toggle — index into names.
        names="[]"
        niri msg --json event-stream 2>/dev/null | while IFS= read -r ev; do
          case "$ev" in
            *KeyboardLayoutsChanged*)
              names="$(printf '%s' "$ev" | jq -c '.KeyboardLayoutsChanged.keyboard_layouts.names' 2>/dev/null)" ;;
            *KeyboardLayoutSwitched*)
              idx="$(printf '%s' "$ev" | jq -r '.KeyboardLayoutSwitched.idx' 2>/dev/null)"
              name="$(printf '%s' "$names" | jq -r ".[$idx] // empty" 2>/dev/null)"
              [ -n "$name" ] && wayle toast "$name" --icon ld-keyboard-symbolic --duration 1000 ;;
          esac
        done
        ;;
      hypr)
        sock="$rt/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"
        [ -S "$sock" ] || exit 0
        # activelayout>>KEYBOARD,LAYOUT_NAME. Hyprland fires one event per
        # keyboard at connect/startup; skip the first 3s so login is quiet.
        start="$(date +%s)"
        socat -U - "UNIX-CONNECT:$sock" 2>/dev/null | while IFS= read -r line; do
          case "$line" in
            activelayout\>\>*)
              [ "$(($(date +%s) - start))" -lt 3 ] && continue
              wayle toast "${line##*,}" --icon ld-keyboard-symbolic --duration 1000 ;;
          esac
        done
        ;;
    esac
    ;;

  *) exit 0 ;;
esac
