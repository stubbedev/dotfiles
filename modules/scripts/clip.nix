# clip: the clipboard shim every script and binding pipes through.
_: {
  flake.modules.homeManager.script-clip =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      displaySinks = lib.optionals config.features.desktop [
        "sink_wayland"
        "sink_x11"
      ];
      terminalSinks = [
        "sink_tmux"
        "sink_osc52"
      ];

      clip = pkgs.stubbe.bashApp {
        name = "clip";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          data=$(if [ "$#" -gt 0 ]; then printf '%s' "$*"; else cat; fi)
          [ -n "$data" ] || exit 0

          if [ -n "''${TMUX:-}" ]; then
            printf '%s' "$data" | tmux load-buffer - 2>/dev/null || true
          fi

          ${lib.optionalString config.features.desktop ''
            sink_wayland() {
              [ -n "''${WAYLAND_DISPLAY:-}" ] || return 1
              printf '%s' "$data" | ${lib.getExe' pkgs.wl-clipboard "wl-copy"}
            }

            sink_x11() {
              [ -n "''${DISPLAY:-}" ] || return 1
              printf '%s' "$data" | ${lib.getExe pkgs.xclip} -selection clipboard
            }
          ''}

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
            sinks=(${lib.concatStringsSep " " (terminalSinks ++ displaySinks)})
          else
            sinks=(${lib.concatStringsSep " " (displaySinks ++ terminalSinks)})
          fi

          for sink in "''${sinks[@]}"; do
            if "$sink"; then
              exit 0
            fi
          done

          echo "clip: no clipboard reachable (${lib.optionalString config.features.desktop "no Wayland/X11, "}no tmux, no writable /dev/tty)" >&2
          exit 1
        '';
      };
    in
    {
      home.packages = [ clip ];
    };
}
