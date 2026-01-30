{ ... }:
{
  flake.modules.homeManager.themeDconf = { ... }:
    {
      # Configure dconf (GNOME settings) to prefer dark mode
      dconf.settings = {
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          gtk-theme = "Adwaita";
          icon-theme = "Vimix-dark";
          cursor-theme = "Vimix-cursors";
        };
      };
    };
}
