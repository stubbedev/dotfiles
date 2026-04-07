#!/bin/bash

# Listen for Hyprland openwindow events and resize floating JetBrains popup
# windows by +1px height. Run via exec-once in settings.conf.

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

socat -U - "UNIX-CONNECT:$SOCKET" | while read -r line; do
    # openwindow>>address,workspace,class,title
    [[ "$line" != openwindow* ]] && continue

    ADDRESS="0x${line#openwindow>>}"
    ADDRESS="${ADDRESS%%,*}"

    # Fetch window info
    WINDOW=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
for c in clients:
    if c.get('address') == '$ADDRESS':
        cls = c.get('class', '')
        floating = c.get('floating', False)
        w, h = c['size']
        print(cls, int(floating), w, h)
        break
" 2>/dev/null)

    [[ -z "$WINDOW" ]] && continue

    CLASS=$(echo "$WINDOW" | awk '{print $1}')
    FLOATING=$(echo "$WINDOW" | awk '{print $2}')
    W=$(echo "$WINDOW" | awk '{print $3}')
    H=$(echo "$WINDOW" | awk '{print $4}')

    [[ "$CLASS" != jetbrains-* ]] && continue
    [[ "$FLOATING" != "1" ]] && continue

    hyprctl dispatch resizewindowpixel "exact ${W} $((H + 1)),address:${ADDRESS}"
    hyprctl dispatch resizewindowpixel "exact ${W} ${H},address:${ADDRESS}"
done
