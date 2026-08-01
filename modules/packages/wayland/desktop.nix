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
      enabled = config.features.hyprland;

      # Start the compositor's user systemd target. hyprland calls this from
      # its startup hook so services WantedBy hyprland-session.target come up.
      # Usage: compositor-session hyprland
      compositor-session = pkgs.writeShellScriptBin "compositor-session" ''
        set -eu

        self="''${1:?compositor name required (hyprland)}"
        exec ${pkgs.systemd}/bin/systemctl --user start "$self-session.target"
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
