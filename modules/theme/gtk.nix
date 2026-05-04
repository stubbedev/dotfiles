_: {
  flake.modules.homeManager.themeGtk =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.theming {
      gtk = {
        enable = true;

        theme = {
          name = "catppuccin-mocha-mauve-standard";
          package = pkgs.catppuccin-gtk.override {
            variant = "mocha";
            accents = [ "mauve" ];
            size = "standard";
          };
        };

        iconTheme = {
          name = "Tela-circle-purple-dark";
          package = pkgs.tela-circle-icon-theme.override {
            colorVariants = [ "purple" ];
          };
        };

        cursorTheme = {
          name = "Vimix-cursors";
          package = pkgs.vimix-cursors;
          size = 24;
        };

        gtk3.extraConfig = {
          gtk-application-prefer-dark-theme = 1;
        };

        gtk4 = {
          theme = null;
          extraConfig = {
            gtk-application-prefer-dark-theme = 1;
          };
        };
      };
    };
}
