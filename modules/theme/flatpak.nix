{ self, ... }:
{
  flake.modules.homeManager.themeFlatpak =
    {
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.theming {
      home.file = {
        # Flatpak overrides for dark mode theming
        # Note: Qt/KDE flatpaks may have poor contrast because they use the Breeze
        # theme from their runtime, which may be different from your system theme.
        # For better appearance, consider using native packages for Qt apps.
        ".local/share/flatpak/overrides/global".source = self + "/src/flatpak/overrides/global";

        # Steam Flatpak override for X11/GLX support in KDE Wayland
        # Grants access to XDG_RUNTIME_DIR for XAUTHORITY and Discord RPC
        ".local/share/flatpak/overrides/com.valvesoftware.Steam" = {
          source = self + "/src/flatpak/overrides/com.valvesoftware.Steam";
          force = true;
        };
      };
    };
}
