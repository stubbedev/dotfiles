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

      # The portal is a dbus-activated systemd user service and does not
      # inherit Hyprland's `hl.env` directives. src/hypr/hyprland.lua
      # deliberately excludes QT_QPA_PLATFORMTHEME and QT_STYLE_OVERRIDE
      # from dbus-update-activation-environment (breaks KDE Plasma login),
      # so scope them to this unit only — hyprland-share-picker is a Qt
      # child of xdph and reads them from its parent's env.
      xdg.configFile."systemd/user/xdg-desktop-portal-hyprland.service.d/qt-theme.conf".text = ''
        [Service]
        Environment=QT_QPA_PLATFORMTHEME=qt5ct
        Environment=QT_STYLE_OVERRIDE=kvantum
      '';
    };
}
