_: {
  flake.modules.nixos.sddm =
    { pkgs, lib, ... }:
    {
      # greetd comes in as a default elsewhere on the stack; SDDM is the DM.
      services.greetd.enable = lib.mkForce false;

      services.displayManager.sddm = {
        enable = true;
        wayland.enable = true;
        # Default was `weston` (kiosk-shell), which on this stack produced
        # no cursor at all in the greeter — Qt6/Wayland in sddm-greeter
        # apparently never set a cursor surface, and weston-kiosk doesn't
        # render a default one when no client provides one. kwin_wayland
        # is the compositor KDE Plasma ships SDDM with, so cursor handling
        # with the Qt6 greeter is exercised in production. Tradeoff is
        # a heavier closure (kwin pulls more KDE libs).
        wayland.compositor = "kwin";
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

      # libxcursor on this system (v1.2.3) has a compile-time default
      # search path of `~/.local/share/icons:~/.icons:$prefix/share/icons:
      # $prefix/share/pixmaps` (confirmed by `strings libXcursor.so`).
      # It does NOT read XDG_DATA_DIRS, contrary to what the Xcursor
      # man page suggests. The only env var libxcursor respects is
      # XCURSOR_PATH — and SDDM 0.21 strips that from the env it hands
      # to its helper (allowlist in src/daemon/Greeter.cpp:195-205
      # only passes through LANG/LC_*/LD_LIBRARY_PATH/QML2_IMPORT_PATH/
      # QT_PLUGIN_PATH/XDG_DATA_DIRS).
      #
      # User sessions work because home-manager symlinks Vimix-cursors
      # into ~/.local/share/icons/ (first entry of libxcursor's default
      # path). The sddm user (home /var/lib/sddm) has neither, so the
      # greeter renders no cursor at all.
      #
      # Drop a symlink into /var/lib/sddm/.icons (~/.icons for the
      # sddm user) — libxcursor's compile-time default path is
      # `~/.local/share/icons:~/.icons:$prefix/share/icons:…`, and
      # ~/.icons lives directly under sddm's home (no intermediate
      # path-ownership transition).
      #
      # The previous attempt under .local/share/icons fails because
      # systemd-tmpfiles refuses to canonicalize a path where
      # /var/lib/sddm (owned sddm) transitions to .local (created by
      # tmpfiles itself with default root ownership) — CVE-2021-3997
      # safe-path-walk guard. .icons sits at the top level so no
      # transition occurs.
      #
      # `L+` forces re-creation each activation so a Vimix-cursors
      # store-path bump in the system closure is picked up without
      # manual cleanup.
      systemd.tmpfiles.rules = [
        "d /var/lib/sddm/.icons 0755 sddm sddm -"
        "L+ /var/lib/sddm/.icons/Vimix-cursors - sddm sddm - /run/current-system/sw/share/icons/Vimix-cursors"
      ];
    };
}
