# clip: the clipboard shim every script and binding pipes through.
_: {
  flake.modules.homeManager.script-clip =
    { pkgs, ... }:
    let
      clip = pkgs.stubbe.bashApp {
        name = "clip";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''

          data=$(if [ "$#" -gt 0 ]; then printf '%s' "$*"; else cat; fi)
          [ -n "$data" ] || exit 0

          if [ -n "''${TMUX:-}" ]; then
            printf '%s' "$data" | tmux load-buffer - 2>/dev/null || true
          fi

          sink_wayland() {
            [ -n "''${WAYLAND_DISPLAY:-}" ] || return 1
            command -v wl-copy >/dev/null 2>&1 || return 1
            printf '%s' "$data" | wl-copy
          }

          sink_x11() {
            [ -n "''${DISPLAY:-}" ] || return 1
            if command -v xclip >/dev/null 2>&1; then
              printf '%s' "$data" | xclip -selection clipboard
            elif command -v xsel >/dev/null 2>&1; then
              printf '%s' "$data" | xsel --clipboard --input
            else
              return 1
            fi
          }

          sink_macos() {
            command -v pbcopy >/dev/null 2>&1 || return 1
            printf '%s' "$data" | pbcopy
          }

          sink_tmux() {
            [ -n "''${TMUX:-}" ] || return 1
            printf '%s' "$data" | tmux load-buffer -w - 2>/dev/null
          }

          sink_osc52() {
            [ "''${#data}" -le 102400 ] || return 1
            local b64 seq
            b64=$(printf '%s' "$data" | base64 | tr -d '\n')
            seq="\033]52;c;$b64\a"
            if [ -n "''${TMUX:-}" ]; then
              seq="\033Ptmux;\033$seq\033\\"
            fi
            printf '%b' "$seq" 2>/dev/null >/dev/tty
          }

          if [ -n "''${SSH_CONNECTION:-}" ] || [ -n "''${SSH_TTY:-}" ]; then
            sinks=(sink_tmux sink_osc52 sink_wayland sink_x11 sink_macos)
          else
            sinks=(sink_wayland sink_x11 sink_macos sink_tmux sink_osc52)
          fi

          for sink in "''${sinks[@]}"; do
            if "$sink"; then
              exit 0
            fi
          done

          echo "clip: no clipboard reachable (no Wayland/X11/pbcopy, no tmux, no writable /dev/tty)" >&2
          exit 1
        '';
      };
    in
    {
      home.packages = [ clip ];
    };
}
