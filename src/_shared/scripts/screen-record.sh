#!/usr/bin/env bash
set -euo pipefail

# Toggle desktop recording with gpu-screen-recorder, driven from a waybar
# widget and compositor keybinds. Records the currently focused monitor.
# Works on any GPU (AMD/Intel/NVIDIA): h264 maps to whatever hardware encoder
# the card exposes (VAAPI / NVENC), and KMS capture is promptless wherever the
# gsr-kms-server setcap wrapper is installed (the NixOS module does this for
# every vendor; non-NixOS may prompt once via polkit). Audio is captured as
# two separate tracks: system playback and the default mic.
#
# Optional webcam overlay (`--cam`): pick a region with slurp, record the
# webcam to a sidecar file in parallel, and mux it into the final mp4 on
# stop. Skipped automatically when the cam device is missing or the first
# few frames are dark (lens cap / disabled).

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PID_FILE="$RUNTIME_DIR/gpu-screen-recorder.pid"
CAM_PID_FILE="$RUNTIME_DIR/gpu-screen-recorder-cam.pid"
META_FILE="$RUNTIME_DIR/gpu-screen-recorder.meta"
LOG_FILE="$RUNTIME_DIR/gpu-screen-recorder.log"
CAM_LOG_FILE="$RUNTIME_DIR/gpu-screen-recorder-cam.log"
OUTPUT_DIR="$HOME/Videos/Recordings"

FPS=60
VIDEO_CODEC=h264
QUALITY=very_high

CAM_DEVICE="${SCREEN_RECORD_CAM:-/dev/video0}"
CAM_CAPTURE_SIZE="${SCREEN_RECORD_CAM_SIZE:-640x480}"
CAM_FRAMERATE="${SCREEN_RECORD_CAM_FPS:-30}"
# Mean luma 0-255 below which the cam is considered dark (lens cap / off).
CAM_DARK_THRESHOLD="${SCREEN_RECORD_CAM_DARK:-15}"

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

load_meta() {
  START=0
  OUTPUT=""
  CAM_OUTPUT=""
  CAM_X=0
  CAM_Y=0
  CAM_W=0
  CAM_H=0
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
  rm -f "$PID_FILE"
  return 1
}

cam_is_running() {
  [ -f "$CAM_PID_FILE" ] || return 1
  local pid
  pid=$(cat "$CAM_PID_FILE" 2>/dev/null || true)
  [ -n "$pid" ] || { rm -f "$CAM_PID_FILE"; return 1; }
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  rm -f "$CAM_PID_FILE"
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

# Logical origin of the focused output in compositor coords. Slurp returns
# global coords; ffmpeg overlay needs them relative to the captured monitor.
focused_origin() {
  local x=0 y=0
  if [ -n "${NIRI_SOCKET:-}" ] && command -v niri >/dev/null 2>&1; then
    read -r x y < <(niri msg --json focused-output 2>/dev/null \
      | jq -r '.logical | "\(.x) \(.y)"' 2>/dev/null) || true
  elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
    read -r x y < <(hyprctl monitors -j 2>/dev/null \
      | jq -r 'first(.[]|select(.focused==true)) | "\(.x) \(.y)"' 2>/dev/null) || true
  fi
  printf '%s %s' "${x:-0}" "${y:-0}"
}

cam_available() {
  [ -e "$CAM_DEVICE" ] || return 1
  command -v ffmpeg >/dev/null 2>&1 || return 1
  return 0
}

# Capture a few frames and read the mean luma reported by ffmpeg's signalstats
# filter. The leading frames are skipped because most cams produce a dark
# burst before auto-exposure settles. Returns 0 if the cam looks live, 1 if
# it looks dark (or probe failed).
cam_is_lit() {
  local lum out
  out=$(ffmpeg -hide_banner -nostdin -loglevel info \
    -f v4l2 -i "$CAM_DEVICE" \
    -vf "select=gte(n\,5),signalstats,metadata=print" \
    -frames:v 1 -f null - 2>&1) || return 1
  lum=$(printf '%s\n' "$out" | grep -oE 'YAVG:[0-9.]+' | tail -1 | cut -d: -f2) || true
  [ -n "$lum" ] || return 1
  awk -v v="$lum" -v t="$CAM_DARK_THRESHOLD" 'BEGIN{exit !(v+0 >= t+0)}'
}

# Use slurp to pick the overlay region. Returns "gx gy gw gh" in global coords
# on stdout. Empty stdout on cancel.
pick_cam_region() {
  command -v slurp >/dev/null 2>&1 || return 0
  slurp -f '%x %y %w %h' 2>/dev/null || true
}

start_cam_recorder() {
  local output="$1"
  setsid bash -c '
    echo $$ > "$1"
    shift
    exec ffmpeg -hide_banner -nostdin -loglevel warning \
      -f v4l2 -framerate "$1" -video_size "$2" -i "$3" \
      -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
      -y "$4"
  ' _ "$CAM_PID_FILE" "$CAM_FRAMERATE" "$CAM_CAPTURE_SIZE" "$CAM_DEVICE" "$output" \
    </dev/null >"$CAM_LOG_FILE" 2>&1 &
  disown
}

start() {
  local want_cam="${1:-0}"

  is_running && return 0

  mkdir -p "$OUTPUT_DIR"
  local output target ts
  target=$(focused_output)
  ts=$(date +%Y-%m-%d_%H-%M-%S)
  output="$OUTPUT_DIR/recording_${ts}.mp4"

  local cam_output="" cam_x=0 cam_y=0 cam_w=0 cam_h=0
  if [ "$want_cam" = "1" ]; then
    if ! cam_available; then
      notify "Cam unavailable" "$CAM_DEVICE missing — recording without overlay"
      want_cam=0
    fi
  fi

  if [ "$want_cam" = "1" ]; then
    local geom
    geom=$(pick_cam_region)
    if [ -z "$geom" ]; then
      notify "Cam overlay cancelled" "Recording without overlay"
      want_cam=0
    else
      local gx gy gw gh ox oy
      read -r gx gy gw gh <<<"$geom"
      read -r ox oy <<<"$(focused_origin)"
      cam_x=$(( gx - ox ))
      cam_y=$(( gy - oy ))
      cam_w=$gw
      cam_h=$gh
      if [ "$cam_w" -le 0 ] || [ "$cam_h" -le 0 ]; then
        want_cam=0
      fi
    fi
  fi

  if [ "$want_cam" = "1" ]; then
    if ! cam_is_lit; then
      notify "Cam appears dark" "Skipping overlay (lens cap / disabled?)"
      want_cam=0
    fi
  fi

  if [ "$want_cam" = "1" ]; then
    cam_output="$OUTPUT_DIR/.cam_${ts}.mkv"
  fi

  {
    printf 'START=%s\n' "$(date +%s)"
    printf 'OUTPUT=%s\n' "$output"
    printf 'CAM_OUTPUT=%s\n' "$cam_output"
    printf 'CAM_X=%s\nCAM_Y=%s\nCAM_W=%s\nCAM_H=%s\n' "$cam_x" "$cam_y" "$cam_w" "$cam_h"
  } > "$META_FILE"

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

  sleep 0.6
  if ! is_running; then
    rm -f "$META_FILE"
    notify -u critical "Recording failed to start" "$(tail -n 3 "$LOG_FILE" 2>/dev/null)"
    refresh_waybar
    return 1
  fi

  if [ -n "$cam_output" ]; then
    start_cam_recorder "$cam_output"
    sleep 0.4
    if ! cam_is_running; then
      notify "Cam recorder failed" "$(tail -n 3 "$CAM_LOG_FILE" 2>/dev/null)"
      rm -f "$CAM_PID_FILE"
      cam_output=""
      # Strip cam fields from meta so stop() doesn't try to mux.
      sed -i 's|^CAM_OUTPUT=.*|CAM_OUTPUT=|' "$META_FILE" || true
    fi
  fi

  notify "Recording started" "$target → $(basename "$output")${cam_output:+ (+cam)}"
  refresh_waybar
}

mux_cam() {
  local screen="$1" cam="$2" out="$3" x="$4" y="$5" w="$6" h="$7"
  command -v ffmpeg >/dev/null 2>&1 || return 1
  [ -s "$cam" ] || return 1

  ffmpeg -hide_banner -nostdin -loglevel warning \
    -i "$screen" -i "$cam" \
    -filter_complex "[1:v]scale=${w}:${h}[c];[0:v][c]overlay=${x}:${y}:shortest=0" \
    -map 0:a? -c:a copy \
    -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p \
    -y "$out"
}

stop() {
  is_running || { rm -f "$META_FILE" "$CAM_PID_FILE"; refresh_waybar; return 0; }

  local pid cam_pid
  pid=$(cat "$PID_FILE" 2>/dev/null || true)
  cam_pid=$(cat "$CAM_PID_FILE" 2>/dev/null || true)
  load_meta
  local output="$OUTPUT" cam_output="$CAM_OUTPUT"

  # SIGINT makes gpu-screen-recorder finalize the container before exiting;
  # SIGTERM/SIGKILL would leave an unplayable file. ffmpeg also finalizes on
  # SIGINT.
  kill -INT "$pid" 2>/dev/null || true
  [ -n "$cam_pid" ] && kill -INT "$cam_pid" 2>/dev/null || true

  for _ in $(seq 1 40); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  if [ -n "$cam_pid" ]; then
    for _ in $(seq 1 40); do
      kill -0 "$cam_pid" 2>/dev/null || break
      sleep 0.25
    done
  fi

  rm -f "$PID_FILE" "$CAM_PID_FILE" "$META_FILE"

  local final="$output"
  if [ -n "$cam_output" ] && [ -s "$cam_output" ] && [ -n "$output" ] && [ -f "$output" ]; then
    local muxed="${output%.mp4}_cam.mp4"
    if mux_cam "$output" "$cam_output" "$muxed" "$CAM_X" "$CAM_Y" "$CAM_W" "$CAM_H"; then
      rm -f "$output" "$cam_output"
      mv "$muxed" "$output"
      final="$output"
    else
      notify -u critical "Cam mux failed" "Kept raw files: $(basename "$output"), $(basename "$cam_output")"
    fi
  elif [ -n "$cam_output" ] && [ -f "$cam_output" ]; then
    rm -f "$cam_output"
  fi

  if [ -n "$final" ] && [ -f "$final" ]; then
    notify "Recording saved" "$final"
  else
    notify "Recording stopped" ""
  fi
  refresh_waybar
}

toggle() {
  local want_cam="${1:-0}"
  if is_running; then
    stop
  else
    start "$want_cam"
  fi
}

status() {
  if ! is_running; then
    printf '{"text":" ","alt":"idle","class":"idle","tooltip":"Screen recorder idle — click to record focused monitor, middle-click for cam overlay"}\n'
    return 0
  fi

  local start_ts now elapsed h m s clock output cam
  load_meta
  start_ts="${START:-0}"
  output="$OUTPUT"
  cam="$CAM_OUTPUT"
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

  local icon=" "
  [ -n "$cam" ] && icon="󰖠 "
  printf '{"text":"%s%s","alt":"recording","class":"recording","tooltip":"Recording → %s%s"}\n' \
    "$icon" "$clock" "${output:-?}" "${cam:+ (+cam)}"
}

# Parse flags: --cam anywhere flips want_cam on.
WANT_CAM=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --cam|-c) WANT_CAM=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]:-status}"

case "${1:-status}" in
  status) status ;;
  start)  start "$WANT_CAM" ;;
  stop)   stop ;;
  toggle) toggle "$WANT_CAM" ;;
  *)
    echo "Usage: $0 [status|start|stop|toggle] [--cam]" >&2
    exit 1
    ;;
esac
