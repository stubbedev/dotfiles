_: {
  flake.modules.homeManager.packagesHyprlandWayland =
    {
      pkgs,
      homeLib,
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
