_: {
  flake.modules.homeManager.packagesNiriPortal =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.niri {
      home.packages = with pkgs; [
        xdg-desktop-portal-gnome
      ];
    };
}
