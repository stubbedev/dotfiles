#!/usr/bin/env bash
# Resize the focused column/window by a pixel delta with two boundaries:
#
#  - Soft snap: when a delta crosses into ±SNAP_PX of the "all-tiles-fit"
#    point (output minus the other on-screen tiles), the result snaps to
#    that point from either direction. Pressing again past the snap exits the
#    zone and resumes normal stepping, so you can still grow/shrink beyond it.
#
#  - Hard cap: a single column or window can never exceed the focused
#    output's logical dimensions. Within SNAP_PX of the cap, the result
#    snaps to exactly the cap.
#
# set-column-width / set-window-height take inner-window pixels, while
# we compare in tile space (which includes borders), so the script
# converts at dispatch time. The per-axis border total comes from the
# focused window's IPC (tile_size - window_size); a hardcoded value
# would be wrong on fractional-scale outputs where niri rounds the
# border to integer physical pixels (e.g. 1px logical border becomes
# ~1.33px logical at scale 1.5).
#
# Usage:
#   resize-clamped.sh column <delta>          # +N or -N
#   resize-clamped.sh window-height <delta>
set -euo pipefail

SNAP=${NIRI_RESIZE_SNAP_PX:-10%}
MIN_TILE_PX=${NIRI_RESIZE_MIN_PX:-100}

target=$1
delta=$2

output_json=$(niri msg --json focused-output)
window_json=$(niri msg --json focused-window 2>/dev/null || printf '{}')
windows_json=$(niri msg --json windows 2>/dev/null || printf '[]')

out_w=$(printf '%s' "$output_json" | jq -r '.logical.width // empty')
out_h=$(printf '%s' "$output_json" | jq -r '.logical.height // empty')

case "$delta" in
  *%)
    percent=${delta%\%}
    percent_n=${percent#[-+]}
    case "$target" in
      column)
        [ -n "$out_w" ] || { echo "cannot use percentage width without focused output" >&2; exit 1; }
        delta=$(((out_w * percent_n) / 100))
        ;;
      window-height)
        [ -n "$out_h" ] || { echo "cannot use percentage height without focused output" >&2; exit 1; }
        delta=$(((out_h * percent_n) / 100))
        ;;
    esac
    if [ "${percent#-}" != "$percent" ]; then
      delta=-$delta
    else
      delta=+$delta
    fi
    ;;
esac

snap_for_axis() {
  local axis_size=$1

  case "$SNAP" in
    *%)
      local percent=${SNAP%\%}
      printf '%s\n' "$(((axis_size * percent) / 100))"
      ;;
    *)
      printf '%s\n' "$SNAP"
      ;;
  esac
}

ws_id=$(printf '%s' "$window_json" | jq -r '.workspace_id // empty')
focused_col=$(printf '%s' "$window_json" | jq -r '.layout.pos_in_scrolling_layout[0] // empty')
focused_row=$(printf '%s' "$window_json" | jq -r '.layout.pos_in_scrolling_layout[1] // empty')
cur_w=$(printf '%s' "$window_json" | jq -r '.layout.tile_size[0] // 0 | floor')
cur_h=$(printf '%s' "$window_json" | jq -r '.layout.tile_size[1] // 0 | floor')

# Total border thickness per axis (left+right or top+bottom). Read from
# the focused window so it tracks the real rendered geometry, including
# fractional-scale rounding. Falls back to 0 if either size is missing.
border_w=$(printf '%s' "$window_json" | jq -r '
  if .layout.tile_size and .layout.window_size
  then (.layout.tile_size[0] - .layout.window_size[0]) | ceil
  else 0 end
')
border_h=$(printf '%s' "$window_json" | jq -r '
  if .layout.tile_size and .layout.window_size
  then (.layout.tile_size[1] - .layout.window_size[1]) | ceil
  else 0 end
')

# Strip leading + so $((...)) handles signed arithmetic uniformly.
delta_n=${delta#+}

# Sum tile widths of all OTHER columns in this workspace (one tile per column).
# Floating windows have null pos_in_scrolling_layout — skip them.
others_tile_w=$(printf '%s' "$windows_json" | jq -r --argjson ws "${ws_id:-0}" --argjson fc "${focused_col:-0}" '
  [ .[]
    | select(.workspace_id == $ws)
    | select(.layout.pos_in_scrolling_layout != null)
    | {col: .layout.pos_in_scrolling_layout[0], w: .layout.tile_size[0]}
  ]
  | group_by(.col)
  | map(.[0])
  | map(select(.col != $fc))
  | map(.w)
  | add // 0
  | floor
')

# Sum tile heights of OTHER rows in the focused column (one tile per row).
others_tile_h=$(printf '%s' "$windows_json" | jq -r --argjson ws "${ws_id:-0}" --argjson fc "${focused_col:-0}" --argjson fr "${focused_row:-0}" '
  [ .[]
    | select(.workspace_id == $ws)
    | select(.layout.pos_in_scrolling_layout != null)
    | select(.layout.pos_in_scrolling_layout[0] == $fc)
    | {row: .layout.pos_in_scrolling_layout[1], h: .layout.tile_size[1]}
  ]
  | group_by(.row)
  | map(.[0])
  | map(select(.row != $fr))
  | map(.h)
  | add // 0
  | floor
')

dispatch_width() {
  # arg: target tile width — convert to inner window width for set-column-width.
  local tile=$1
  local win=$((tile - border_w))
  [ "$win" -lt 1 ] && win=1
  niri msg action set-column-width "$win"
}

dispatch_height() {
  local tile=$1
  local win=$((tile - border_h))
  [ "$win" -lt 1 ] && win=1
  niri msg action set-window-height "$win"
}

case "$target" in
  column)
    [ -n "$out_w" ] || { niri msg action set-column-width "$delta"; exit 0; }
    snap_px=$(snap_for_axis "$out_w")
    new_tile=$((cur_w + delta_n))
    # Soft boundary: tile width that lets every column on this workspace fit.
    soft=$((out_w - others_tile_w))
    # Hard boundary: a single column can never exceed the monitor itself.
    hard=$out_w
    if [ "$delta_n" -gt 0 ]; then
      if [ "$cur_w" -lt "$soft" ] && [ "$new_tile" -ge $((soft - snap_px)) ]; then
        dispatch_width "$soft"
      elif [ "$new_tile" -ge "$hard" ] || [ $((hard - new_tile)) -le "$snap_px" ]; then
        dispatch_width "$hard"
      else
        niri msg action set-column-width "$delta"
      fi
    elif [ "$new_tile" -le "$MIN_TILE_PX" ]; then
      dispatch_width "$MIN_TILE_PX"
    elif [ "$cur_w" -gt "$soft" ] && [ "$new_tile" -le $((soft + snap_px)) ]; then
      dispatch_width "$soft"
    else
      niri msg action set-column-width "$delta"
    fi
    ;;
  window-height)
    [ -n "$out_h" ] || { niri msg action set-window-height "$delta"; exit 0; }
    snap_px=$(snap_for_axis "$out_h")
    new_tile=$((cur_h + delta_n))
    soft=$((out_h - others_tile_h))
    hard=$out_h
    if [ "$delta_n" -gt 0 ]; then
      if [ "$cur_h" -lt "$soft" ] && [ "$new_tile" -ge $((soft - snap_px)) ]; then
        dispatch_height "$soft"
      elif [ "$new_tile" -ge "$hard" ] || [ $((hard - new_tile)) -le "$snap_px" ]; then
        dispatch_height "$hard"
      else
        niri msg action set-window-height "$delta"
      fi
    elif [ "$new_tile" -le "$MIN_TILE_PX" ]; then
      dispatch_height "$MIN_TILE_PX"
    elif [ "$cur_h" -gt "$soft" ] && [ "$new_tile" -le $((soft + snap_px)) ]; then
      dispatch_height "$soft"
    else
      niri msg action set-window-height "$delta"
    fi
    ;;
  *)
    echo "usage: $0 {column|window-height} <delta>" >&2
    exit 2
    ;;
esac
