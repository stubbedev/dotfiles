_: {
  # Same reasoning as hyprland/portal.nix: on NixOS the portal binary is
  # owned by the system xdg.portal extraPortals list.
  linuxOnlyHomeModules.packagesNiriPortal =
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
