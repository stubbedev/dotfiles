_: {
  flake.modules.homeManager.packagesHyprlandPortal =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.hyprland {
      home.packages = with pkgs; [
        hyprwire
        hyprland-protocols
        xdg-desktop-portal
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-wlr
      ];
    };
}
