_: {
  flake.modules.homeManager.packagesWaylandPortal =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      enabled = config.features.hyprland || config.features.niri;
    in
    lib.mkIf enabled {
      home.packages = with pkgs; [
        xdg-desktop-portal
      ];
    };
}
