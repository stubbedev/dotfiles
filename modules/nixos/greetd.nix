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

      # SDDM 0.21 (src/daemon/Greeter.cpp:195-205) builds the env it
      # hands to sddm-helper (which then spawns weston + sddm-greeter)
      # by *allowlisting* keys from its own systemEnvironment — only
      # LANG/LC_*/LD_LIBRARY_PATH/QML2_IMPORT_PATH/QT_PLUGIN_PATH/
      # XDG_DATA_DIRS get pulled through, the rest are dropped. So
      # XCURSOR_PATH on this unit is silently discarded before reaching
      # weston, which is why a plain `XCURSOR_PATH=...` had no effect.
      #
      # XDG_DATA_DIRS *is* in the allowlist, and libxcursor's search
      # path expands to `$XDG_DATA_HOME/icons:$XDG_DATA_DIRS/icons:…`
      # (Xcursor man page). Setting XDG_DATA_DIRS here to the system
      # profile gets `/run/current-system/sw/share/icons/Vimix-cursors`
      # found by weston's libxcursor.
      #
      # The unit name is `display-manager`, not `sddm` — NixOS sddm
      # module wires service config via systemd.services.display-manager
      # (nixos/modules/services/display-managers/sddm.nix:13).
      systemd.services.display-manager.environment.XDG_DATA_DIRS =
        "/run/current-system/sw/share";
    };
}
