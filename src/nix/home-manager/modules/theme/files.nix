{ ... }:
{
  flake.modules.homeManager.themeFiles = { constants, pkgs, lib, config, ... }:
    lib.mkIf config.features.theming {
      home.file = {
        ".icons/${constants.theme.iconTheme}".source =
          "${pkgs.vimix-icon-theme}/share/icons/Vimix-dark";
        ".icons/Vimix-cursors".source =
          "${pkgs.vimix-cursors}/share/icons/Vimix-cursors";

        # Also symlink to .local/share/icons for better compatibility
        ".local/share/icons/Vimix-dark".source =
          "${pkgs.vimix-icon-theme}/share/icons/Vimix-dark";
        ".local/share/icons/Vimix-cursors".source =
          "${pkgs.vimix-cursors}/share/icons/Vimix-cursors";
        ".themes/${constants.theme.gtkTheme}".source =
          "${pkgs.rose-pine-gtk-theme}/share/themes/rose-pine";
      };
    };
}
