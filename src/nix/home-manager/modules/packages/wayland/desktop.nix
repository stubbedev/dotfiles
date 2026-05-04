_: {
  flake.modules.homeManager.packagesWaylandDesktop =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      enabled = config.features.hyprland || config.features.niri;

      # swaync wrapper that auto-detects the Wayland display socket.
      # Needed when swaync is launched before WAYLAND_DISPLAY is set
      # (e.g. from a display manager or early autostart).
      swaync-wrapped = pkgs.writeShellScriptBin "swaync" ''
        # A Wayland socket file alone isn't proof a compositor is alive — when a
        # compositor exits abnormally (or libwayland falls back to wayland-2
        # because wayland-1 is taken, then exits) the socket file lingers.
        # libwayland's lock file is held with flock by the live compositor, so
        # a non-blocking flock that succeeds means nobody owns the socket.
        _wayland_live() {
          local display="$1"
          local sock="$XDG_RUNTIME_DIR/$display"
          local lock="$XDG_RUNTIME_DIR/$display.lock"
          [ -S "$sock" ] || return 1
          [ -e "$lock" ] || return 1
          ! flock -n -x "$lock" true 2>/dev/null
        }

        if [ -n "$WAYLAND_DISPLAY" ] && _wayland_live "$WAYLAND_DISPLAY"; then
          :
        else
          unset WAYLAND_DISPLAY
          attempt=0
          while [ $attempt -lt 50 ] && [ -z "$WAYLAND_DISPLAY" ]; do
            for socket in $(ls -t "$XDG_RUNTIME_DIR"/wayland-[0-9]* 2>/dev/null | grep -E 'wayland-[0-9]+$'); do
              candidate=$(basename "$socket")
              if _wayland_live "$candidate"; then
                export WAYLAND_DISPLAY="$candidate"
                break
              fi
            done
            if [ -z "$WAYLAND_DISPLAY" ]; then
              sleep 0.1
            fi
            attempt=$((attempt + 1))
          done
        fi

        if [ -z "$WAYLAND_DISPLAY" ] || ! _wayland_live "$WAYLAND_DISPLAY"; then
          echo "No live Wayland compositor found, retrying via systemd" >&2
          exit 1
        fi

        export GDK_BACKEND=wayland
        exec ${pkgs.swaynotificationcenter}/bin/swaync "$@"
      '';

      # Switch the active compositor's user systemd target. Stops the other
      # known compositor session targets, then starts the named one. Both
      # niri and hyprland call this from their startup hooks so services
      # PartOf <other>-session.target don't leak across switches.
      # Usage: compositor-session <niri|hyprland>
      compositor-session = pkgs.writeShellScriptBin "compositor-session" ''
        set -eu

        self="''${1:?compositor name required (niri|hyprland)}"
        self_target="$self-session.target"

        # Add new compositors to this list as needed.
        for target in niri-session.target hyprland-session.target; do
          if [ "$target" != "$self_target" ]; then
            ${pkgs.systemd}/bin/systemctl --user stop "$target" 2>/dev/null || true
          fi
        done

        exec ${pkgs.systemd}/bin/systemctl --user start "$self_target"
      '';
    in
    lib.mkIf enabled {
      home.packages = with pkgs; [
        (homeLib.gfx waybar)
        swaync-wrapped
        compositor-session
        (homeLib.gfx rofi)
        (homeLib.gfx bemenu)
        wl-clipboard
        wl-clip-persist
      ];
    };
}
