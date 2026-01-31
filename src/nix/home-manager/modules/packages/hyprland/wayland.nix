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
        wlprop
        wayland-scanner
        wayland-utils
        (homeLib.gfx slurp)
        (homeLib.gfx grim)
        wl-clip-persist
      ];
    };
}
