_: {
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      # HM-side modules/theme/dconf.nix writes dconf keys (color-scheme,
      # blueman). On NixOS, the dconf service must be enabled system-wide
      # for the HM dconf module to apply settings — otherwise activation
      # errors with "dconf is not enabled".
      programs.dconf.enable = true;

      # GTK applications consult xdg-desktop-portal for file pickers,
      # screen sharing, etc. portal.nix already enables the service; this
      # is the explicit GSettings dependency that pulls in the schema.
      services.gnome.gnome-keyring.enable = true;

      # Qt platform theming. qt5ct/qt6ct read ~/.config/qt5ct/qt5ct.conf
      # (managed by modules/theme/qt.nix) which delegates rendering to the
      # Kvantum engine. Kvantum picks up Catppuccin-Mocha-Mauve from
      # ~/.config/Kvantum/kvantum.kvconfig (also managed by that module).
      qt = {
        enable = true;
        platformTheme = "qt5ct";
      };

      # Route GTK apps (notably Firefox) through their Wayland backends so
      # libinput touchpad gestures — two-finger scroll, pinch-zoom, swipe
      # back/forward — reach the application instead of getting swallowed
      # by XWayland's lack of XInput2 gesture support. MOZ_USE_XINPUT2
      # covers the X11-fallback path.
      environment.sessionVariables = {
        MOZ_ENABLE_WAYLAND = "1";
        MOZ_USE_XINPUT2 = "1";
      };

      # Provides the Catppuccin-Mocha-Mauve Kvantum theme files.
      # The Qt5 plugin (libsForQt5.qtstyleplugin-kvantum) and Qt6 plugin
      # (kdePackages.qtstyleplugin-kvantum) are installed via home-manager
      # modules/packages/theming.nix so they land in the user profile.
      environment.systemPackages = [
        pkgs.catppuccin-kvantum
        # Waybar plugins (e.g. the custom power-profile script) require python3.
        pkgs.python3
        pkgs.imgcat
      ];
    };
}
