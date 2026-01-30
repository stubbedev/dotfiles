{ ... }:
{
  flake.modules.homeManager.themeFlatpak = { ... }:
    {
      home.file = {
        # Flatpak overrides for dark mode theming
        # Note: Qt/KDE flatpaks may have poor contrast because they use the Breeze
        # theme from their runtime, which may be different from your system theme.
        # For better appearance, consider using native packages for Qt apps.
        ".local/share/flatpak/overrides/global".text = ''
          [Context]
          filesystems=xdg-config/gtk-3.0:ro;xdg-config/gtk-4.0:ro;~/.themes:ro;~/.icons:ro;/nix/store:ro

          [Environment]
          GTK_THEME=Adwaita-dark
          QT_QPA_PLATFORMTHEME=kde
          QT_STYLE=breeze
          COLOR_SCHEME=prefer-dark
          GDK_BACKEND=wayland,x11
        '';

        # Steam Flatpak override for X11/GLX support in KDE Wayland
        # Grants access to XDG_RUNTIME_DIR for XAUTHORITY and Discord RPC
        ".local/share/flatpak/overrides/com.valvesoftware.Steam" = {
          text = ''
            [Context]
            filesystems=/run/user/1000
          '';
          force = true;
        };
      };
    };
}
