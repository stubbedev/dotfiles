#!/usr/bin/env bash
# Reshape waybar-style status scripts' JSON for wayle's custom modules: drop
# the nerd-font glyph from `text` (wayle shows its own icon-name instead) and
# surface a clean value. tooltip/class preserved for hover + styling.
#
# Every mode is event-driven (wayle `mode = "watch"`): emit the current line,
# then re-emit on each real state change — no polling. Sources:
#   mail        inotify on the notmuch maildir (new/cur)
#   treeman     `treeman logs tail --follow` event stream
#   screenrec   inotify on the gpu-screen-recorder pid markers
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

vpn_line() {
  case "$1" in
    on) emit_line 'if .class == "connected" then {tooltip} else empty end' vpn-konform-bar status ;;
    connecting) emit_line 'if .class == "connecting" then {tooltip} else empty end' vpn-konform-bar status ;;
    off) emit_line 'if (.class == "connected" or .class == "connecting") then empty else {tooltip} end' vpn-konform-bar status ;;
    *) echo ;;
  esac
}

mail_line() { emit_line 'if (.text | test("[0-9]")) then (.text |= gsub("[^0-9]";"")) else empty end' mail-status; }
treeman_line() { emit_line '.text |= (gsub("^[^[:alnum:]]+";"") | gsub("[^[:alnum:]]+$";""))' treeman-status; }
screenrec_line() { emit_line '.text = (if .alt == "recording" then "rec" else "" end)' screen-record status; }

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

  # gpu-screen-recorder pid markers appear/vanish on start/stop. inotifywait
  # --include matches the watched DIR, not the filename, so emit the filename
  # with --format and filter it here.
  screenrec-watch)
    screenrec_line
    inotifywait -q -m -e create,delete,close_write,moved_to,moved_from --format '%f' "$rt" 2>/dev/null |
      while IFS= read -r f; do
        case "$f" in gpu-screen-recorder*.pid) screenrec_line ;; esac
      done
    ;;

  # VPN state changes from two sources, both event-driven:
  #   - the .connecting marker (inotify) → the in-flight "connecting" state
  #   - the oc-konform tunnel interface up/down (ip monitor) → connected /
  #     disconnected. The interface is the ground truth: on disconnect the
  #     openconnect PROCESS dies (no reliable marker-file event — disconnect.sh
  #     can leave the pid file behind), but the kernel always reports the link
  #     going down, so this catches the disconnect the file-watch missed.
  vpn-watch)
    vpn_line "$2"
    {
      inotifywait -q -m -e create,delete,close_write,moved_to,moved_from --format '%f' "$rt" 2>/dev/null &
      ip monitor link 2>/dev/null &
      wait
    } | while IFS= read -r line; do
      case "$line" in
        openconnect-*.pid | openconnect-*.connecting | *oc-konform*) vpn_line "$2" ;;
      esac
    done
    ;;

  # Power profile as three icon-only, color-coded modules ($2 = the profile
  # this module owns): emits non-empty only when that profile is active, so
  # exactly one shows. Re-emits on the daemon's D-Bus ActiveProfile signal.
  powerprofile-watch)
    want="$2"
    pp() {
      local cur
      cur="$(powerprofilesctl get 2>/dev/null)"
      if [ "$cur" = "$want" ]; then printf '{"alt":"%s"}\n' "$cur"; else echo; fi
    }
    pp
    dbus-monitor --system "type='signal',path=/net/hadess/PowerProfiles,interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'" 2>/dev/null |
      while IFS= read -r line; do
        case "$line" in *ActiveProfile*) pp ;; esac
      done
    ;;

  *) exit 0 ;;
esac
