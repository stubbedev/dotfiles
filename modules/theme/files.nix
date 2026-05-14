_: {
  flake.modules.homeManager.themeFiles =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.theming {
      home.file = {
        ".icons/Vimix-cursors".source = "${pkgs.vimix-cursors}/share/icons/Vimix-cursors";

        # Also symlink under .local/share/icons for libxcursor lookups
        # that prefer the XDG path (Ubuntu 24.04 libXcursor 1.2.3+).
        ".local/share/icons/Vimix-dark".source = "${pkgs.vimix-icon-theme}/share/icons/Vimix-dark";
        ".local/share/icons/Vimix-cursors".source = "${pkgs.vimix-cursors}/share/icons/Vimix-cursors";
      };
    };
}
