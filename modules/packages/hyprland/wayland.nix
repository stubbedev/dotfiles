_: {
  flake.modules.homeManager.packagesHyprlandWayland =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.hyprland {
      home.packages = with pkgs; [
        wayland-scanner
      ];
    };
}
