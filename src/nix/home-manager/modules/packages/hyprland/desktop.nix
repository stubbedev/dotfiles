_: {
  flake.modules.homeManager.packagesHyprlandDesktop =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      # Create swaync wrapper that auto-detects the correct Wayland display
      swaync-wrapped = pkgs.writeShellScriptBin "swaync" ''
        # Auto-detect the correct Wayland display socket
        if [ -z "$WAYLAND_DISPLAY" ] || [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
          attempt=0
          while [ $attempt -lt 50 ] && [ -z "$WAYLAND_DISPLAY" ]; do
            # Find the most recent wayland-* socket
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

        # Ensure GDK uses Wayland backend
        export GDK_BACKEND=wayland

        # Run swaync
        exec ${pkgs.swaynotificationcenter}/bin/swaync "$@"
      '';
    in
    lib.mkIf config.features.hyprland {
      home.packages = with pkgs; [
        (homeLib.gfx waybar)
        (homeLib.gfx ashell)
        swaync-wrapped
        (homeLib.gfx rofi)
        (homeLib.gfx bemenu)
      ];
    };
}
