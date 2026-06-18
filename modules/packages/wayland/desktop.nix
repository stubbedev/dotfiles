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
        compositor-session
        (homeLib.gfx rofi)
        wl-clipboard
        wl-clip-persist
        # `notify-send` + libnotify shared library. wayle owns
        # org.freedesktop.Notifications, but libnotify CLI callers (ad-hoc
        # scripts) silently no-op without the binary on PATH.
        libnotify
      ];
    };
}
