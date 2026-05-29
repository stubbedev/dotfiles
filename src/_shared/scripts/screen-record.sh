#!/usr/bin/env bash
set -euo pipefail

# Toggle desktop recording with gpu-screen-recorder, driven from a waybar
# widget and compositor keybinds. Records the currently focused monitor.
# Works on any GPU (AMD/Intel/NVIDIA): h264 maps to whatever hardware encoder
# the card exposes (VAAPI / NVENC), and KMS capture is promptless wherever the
# gsr-kms-server setcap wrapper is installed (the NixOS module does this for
# every vendor; non-NixOS may prompt once via polkit). Audio is captured as
# two separate tracks: system playback and the default mic.

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PID_FILE="$RUNTIME_DIR/gpu-screen-recorder.pid"
META_FILE="$RUNTIME_DIR/gpu-screen-recorder.meta"
LOG_FILE="$RUNTIME_DIR/gpu-screen-recorder.log"
OUTPUT_DIR="$HOME/Videos/Recordings"

FPS=60
VIDEO_CODEC=h264
QUALITY=very_high

# Wakes up every waybar with `"signal": 9` on its gpu-screen-recorder module.
# Same comm-matching rationale as src/vpn/konform/waybar.sh: match the waybar
# binary (plain or home-manager-wrapped), never the bash launcher wrapper,
# whose default action for unhandled real-time signals is Term.
refresh_waybar() {
  pkill -SIGRTMIN+9 '^\.?waybar(-wrapped)?$' 2>/dev/null || true
}

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Screen Recorder" "$@" || true
}

# Load START / OUTPUT from the meta file into the current shell. Guarded so a
# missing file under `set -e` doesn't abort the caller.
load_meta() {
  START=0
  OUTPUT=""
  if [ -f "$META_FILE" ]; then
    # shellcheck source=/dev/null
    . "$META_FILE" 2>/dev/null || true
  fi
}

is_running() {
  [ -f "$PID_FILE" ] || return 1
  local pid
  pid=$(cat "$PID_FILE" 2>/dev/null || true)
  [ -n "$pid" ] || { rm -f "$PID_FILE"; return 1; }
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  # Stale pid file (process gone).
  rm -f "$PID_FILE"
  return 1
}

# Resolve the connector name (e.g. DP-1) of the focused output so we capture
# just the monitor the user is looking at. gpu-screen-recorder's own `focused`
# target is X11-only, so on Wayland we ask the compositor and pass the name.
# Falls back to `screen` (first monitor found) when detection fails.
focused_output() {
  local name=""
  if [ -n "${NIRI_SOCKET:-}" ] && command -v niri >/dev/null 2>&1; then
    name=$(niri msg --json focused-output 2>/dev/null | jq -r '.name // empty' 2>/dev/null || true)
  elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
    name=$(hyprctl monitors -j 2>/dev/null | jq -r 'first(.[] | select(.focused == true)) | .name // empty' 2>/dev/null || true)
  fi
  if [ -z "$name" ] || [ "$name" = "null" ]; then
    name="screen"
  fi
  printf '%s' "$name"
}

start() {
  is_running && return 0

  mkdir -p "$OUTPUT_DIR"
  local output target
  target=$(focused_output)
  output="$OUTPUT_DIR/recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"

  printf 'START=%s\nOUTPUT=%s\n' "$(date +%s)" "$output" > "$META_FILE"

  # Launch detached in its own session so it survives the waybar/keybind
  # shell that triggered it. The inner bash records its own pid then execs
  # gpu-screen-recorder, so PID_FILE ends up holding the recorder's pid
  # (exec preserves it through the nixGL/makeWrapper chain on non-NixOS).
  setsid bash -c '
    echo $$ > "$1"
    shift
    exec gpu-screen-recorder "$@"
  ' _ "$PID_FILE" \
    -w "$target" \
    -f "$FPS" \
    -k "$VIDEO_CODEC" \
    -q "$QUALITY" \
    -fallback-cpu-encoding yes \
    -a default_output \
    -a default_input \
    -o "$output" \
    </dev/null >"$LOG_FILE" 2>&1 &
  disown

  # Give it a moment to fail fast (bad monitor name, missing capability,
  # no audio device) so the click gets real feedback instead of a silent
  # no-op that leaves the widget stuck "recording".
  sleep 0.6
  if ! is_running; then
    rm -f "$META_FILE"
    notify -u critical "Recording failed to start" "$(tail -n 3 "$LOG_FILE" 2>/dev/null)"
    refresh_waybar
    return 1
  fi

  notify "Recording started" "$target → $(basename "$output")"
  refresh_waybar
}

stop() {
  is_running || { rm -f "$META_FILE"; refresh_waybar; return 0; }

  local pid output
  pid=$(cat "$PID_FILE" 2>/dev/null || true)
  load_meta
  output="$OUTPUT"

  # SIGINT makes gpu-screen-recorder finalize the container before exiting;
  # SIGTERM/SIGKILL would leave an unplayable file.
  kill -INT "$pid" 2>/dev/null || true
  for _ in $(seq 1 40); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done

  rm -f "$PID_FILE" "$META_FILE"

  if [ -n "$output" ] && [ -f "$output" ]; then
    notify "Recording saved" "$output"
  else
    notify "Recording stopped" ""
  fi
  refresh_waybar
}

toggle() {
  if is_running; then
    stop
  else
    start
  fi
}

status() {
  if ! is_running; then
    printf '{"text":" ","alt":"idle","class":"idle","tooltip":"Screen recorder idle — click to record focused monitor"}\n'
    return 0
  fi

  local start_ts now elapsed h m s clock output
  load_meta
  start_ts="${START:-0}"
  output="$OUTPUT"
  case "$start_ts" in
    ''|*[!0-9]*) start_ts=0 ;;
  esac
  now=$(date +%s)
  elapsed=$(( now - start_ts ))
  [ "$elapsed" -lt 0 ] && elapsed=0
  h=$(( elapsed / 3600 ))
  m=$(( (elapsed % 3600) / 60 ))
  s=$(( elapsed % 60 ))
  if [ "$h" -gt 0 ]; then
    clock=$(printf '%d:%02d:%02d' "$h" "$m" "$s")
  else
    clock=$(printf '%02d:%02d' "$m" "$s")
  fi

  printf '{"text":" %s","alt":"recording","class":"recording","tooltip":"Recording → %s"}\n' \
    "$clock" "${output:-?}"
}

case "${1:-status}" in
  status) status ;;
  start) start ;;
  stop) stop ;;
  toggle) toggle ;;
  *)
    echo "Usage: $0 [status|start|stop|toggle]" >&2
    exit 1
    ;;
esac
