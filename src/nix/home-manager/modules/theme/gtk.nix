{ ... }:
{
  flake.modules.homeManager.themeGtk = { pkgs, ... }: {
    gtk = {
      enable = true;

      # Don't set theme - let GTK4 use default with dark preference
      # theme = {
      #   name = "Adwaita";
      #   package = pkgs.adwaita-icon-theme;
      # };

      iconTheme = {
        name = "Vimix-dark";
        package = pkgs.vimix-icon-theme;
      };

      cursorTheme = {
        name = "Vimix-cursors";
        package = pkgs.vimix-cursors;
        size = 24;
      };

      gtk3.extraConfig = { gtk-application-prefer-dark-theme = 1; };

      gtk4.extraConfig = { gtk-application-prefer-dark-theme = 1; };
    };
  };
}
