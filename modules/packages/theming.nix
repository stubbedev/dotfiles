_: {
  flake.modules.homeManager.packagesTheming =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.theming {
      # Symlinks fonts from home.packages into ~/.local/share/fonts and runs
      # fc-cache on activation. Without this, fontconfig only sees fonts in
      # /usr/share — Nix-installed fonts are invisible on non-NixOS hosts.
      fonts.fontconfig.enable = true;

      home.packages = with pkgs; [
        # Fonts
        nerd-fonts.jetbrains-mono
        font-awesome
        adwaita-fonts

        # GTK themes and icons
        adwaita-icon-theme
        vimix-icon-theme
        hicolor-icon-theme
        rose-pine-gtk-theme
        gnome-themes-extra # Includes Adwaita-dark GTK theme
        gtk4-layer-shell

        # Qt themes and configuration tools
        adwaita-qt
        adwaita-qt6
        libsForQt5.qt5ct
        kdePackages.qt6ct
        libsForQt5.qtstyleplugins

        # KDE/Qt theming - Kvantum for dark mode support
        libsForQt5.qtstyleplugin-kvantum
        kdePackages.breeze # Breeze Qt theme
      ];
    };
}
