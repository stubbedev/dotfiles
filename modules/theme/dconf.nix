_: {
  flake.modules.homeManager.themeDconf =
    {
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.theming {
      # Configure dconf (GNOME settings) to prefer dark mode
      dconf.settings = {
        # gtk-theme/icon-theme/cursor-theme are set by home-manager's gtk
        # module (modules/theme/gtk.nix), which writes the same dconf keys —
        # leave them out here to avoid conflicting definitions.
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
        };
        "org/blueman/general" = {
          notification-daemon = true;
        };
      };
    };
}
