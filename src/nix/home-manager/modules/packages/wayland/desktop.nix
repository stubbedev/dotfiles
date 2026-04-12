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
        if [ -z "$WAYLAND_DISPLAY" ] || [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
          attempt=0
          while [ $attempt -lt 50 ] && [ -z "$WAYLAND_DISPLAY" ]; do
            for socket in $(ls -t "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v ".lock"); do
              if [ -S "$socket" ]; then
                export WAYLAND_DISPLAY=$(basename "$socket")
                break
              fi
            done
            if [ -z "$WAYLAND_DISPLAY" ]; then
              sleep 0.1
            fi
            attempt=$((attempt + 1))
          done
        fi
        export GDK_BACKEND=wayland
        exec ${pkgs.swaynotificationcenter}/bin/swaync "$@"
      '';
    in
    lib.mkIf enabled {
      home.packages = with pkgs; [
        (homeLib.gfx waybar)
        swaync-wrapped
        (homeLib.gfx rofi)
        (homeLib.gfx bemenu)
        wl-clipboard
        wl-clip-persist
      ];
    };
}
