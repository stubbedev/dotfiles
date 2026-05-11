_: {
  flake.modules.nixos.greetd =
    { pkgs, lib, ... }:
    {
      services.greetd.enable = lib.mkForce false;

      services.displayManager.sddm = {
        enable = true;
        wayland.enable = true;
        theme = "catppuccin-mocha-mauve";
        extraPackages = [
          pkgs.catppuccin-sddm
          pkgs.vimix-cursors
        ];
        settings = {
          Theme = {
            CursorTheme = "Vimix-cursors";
            CursorSize = 24;
          };
        };
      };

      # SDDM's ThemeDir is /run/current-system/sw/share/sddm/themes, populated
      # via environment.pathsToLink. extraPackages only widens SDDM's PATH —
      # it does not contribute to that themes directory. systemPackages does.
      environment.systemPackages = [
        pkgs.catppuccin-sddm
        pkgs.vimix-cursors
      ];

      # /run/current-system/sw/share/icons only gets populated for packages
      # listed in systemPackages when /share/icons is in pathsToLink. Without
      # this, the Vimix-cursors theme exists in the store but SDDM cannot
      # find it, so kwin_wayland renders an invisible cursor.
      environment.pathsToLink = [ "/share/icons" ];

      # SDDM passes the [Theme] CursorTheme setting to its greeter as
      # XCURSOR_THEME, but the libxcursor lookup falls back to the
      # default search path (~/.icons:/usr/share/icons:/usr/share/pixmaps)
      # — none of which contain Vimix-cursors on NixOS, where the symlink
      # lives at /run/current-system/sw/share/icons. Without XCURSOR_PATH
      # set on the unit, Weston (the greeter's compositor) silently
      # renders the default cursor or none at all. Setting it here
      # propagates through to the child Weston + greeter processes.
      systemd.services.sddm.environment.XCURSOR_PATH = "/run/current-system/sw/share/icons";
    };
}
