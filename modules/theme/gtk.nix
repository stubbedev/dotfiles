_: {
  flake.modules.homeManager.themeGtk =
    {
      pkgs,
      lib,
      config,
      constants,
      ...
    }:
    lib.mkIf config.features.theming {
      gtk = {
        enable = true;

        theme = {
          name = constants.theme.gtk;
          package = pkgs.catppuccin-gtk.override {
            variant = "mocha";
            accents = [ "mauve" ];
            size = "standard";
          };
        };

        iconTheme = {
          name = constants.theme.icon;
          package = pkgs.tela-circle-icon-theme.override {
            colorVariants = [ "purple" ];
          };
        };

        cursorTheme = {
          name = constants.theme.cursor;
          package = pkgs.vimix-cursors;
          size = constants.theme.cursorSize;
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
