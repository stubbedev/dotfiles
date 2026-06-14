#!/usr/bin/env bash
# Screenshot helper backing the Print / SHIFT+Print binds.
#
#   screenshot region   pick a region with slurp, copy PNG to clipboard
#   screenshot output    grab the focused monitor, copy PNG to clipboard
#
# Why a script and not an inline bind: slurp's overlay colours come from a
# Nix wrapper (modules/packages/wayland/tools.nix), cancelling the region
# selector must NOT fall through to a full-screen grab (the old hyprshot
# bug), and we want a notification so it's obvious the shot was taken.
set -euo pipefail

mode="${1:-region}"

notify() { command -v notify-send >/dev/null 2>&1 && notify-send -t 2000 "$@" || true; }

case "$mode" in
  region)
    # Already selecting? Don't stack a second selector. `slurp` here is the
    # Nix-wrapped binary, whose process comm is `.slurp-wrapped`.
    pgrep -x .slurp-wrapped >/dev/null && exit 0
    # slurp exits non-zero on Escape, and prints nothing on an empty drag;
    # guard both so a cancel never grabs the whole screen.
    geom=$(slurp -d) || exit 0
    [ -n "$geom" ] || exit 0
    ;;
  output)
    # Geometry of the currently focused monitor: "X,Y WxH".
    geom=$(hyprctl -j monitors \
      | jq -r 'first(.[] | select(.focused)) | "\(.x),\(.y) \(.width)x\(.height)"')
    ;;
  *)
    echo "usage: screenshot region|output" >&2
    exit 2
    ;;
esac

grim -g "$geom" - | wl-copy --type image/png
notify "Screenshot" "Copied to clipboard"
