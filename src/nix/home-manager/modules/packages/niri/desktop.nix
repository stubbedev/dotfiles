_: {
  flake.modules.homeManager.packagesNiriDesktop =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.niri {
      home.packages = with pkgs; [
        (homeLib.gfx waybar)
        swaynotificationcenter
        (homeLib.gfx rofi)
        wl-clip-persist
        wl-clipboard
      ];
    };
}
