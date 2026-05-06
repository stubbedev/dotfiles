_: {
  # Lives in linuxOnlyHomeModules because on NixOS the system-level
  # xdg.portal.extraPortals (modules/nixos/portal.nix) ships these
  # binaries and ties them into the desktop-portal service. Adding them
  # to home.packages too would just duplicate /nix/store paths in the
  # user profile.
  linuxOnlyHomeModules.packagesHyprlandPortal =
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
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-wlr
      ];
    };
}
