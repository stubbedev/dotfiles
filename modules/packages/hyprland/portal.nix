_: {
  # Lives in linuxOnlyHomeModules because on NixOS the system-level
  # xdg.portal.extraPortals (modules/nixos/portal.nix) ships these
  # binaries and ties them into the desktop-portal service. Adding them
  # to home.packages too would just duplicate /nix/store paths in the
  # user profile.
  linuxOnlyHomeModules.packagesHyprlandPortal =
    {
      pkgs,
      lib,
      config,
      homeLib,
      ...
    }:
    let
      # Screencast picker is wayle's built-in `share-picker` subcommand
      # (replaces the standalone hyprland-preview-share-picker). gfxExe wraps
      # the wayle binary with nixGL on non-NixOS so its GTK4/EGL find drivers;
      # passthrough on NixOS. Its icons resolve from wayle's share/ dir, already
      # on XDG_DATA_DIRS via the wrapped wayle package (modules/home/wayle.nix).
      picker = homeLib.gfxExe "wayle" pkgs.wayle;

      # xdph execs custom_picker_binary with execvp() — NO shell, no word
      # splitting (see CProcess in hyprutils: execvp(binary, args)). So a
      # "wayle share-picker" string is treated as one filename-with-a-space and
      # fails; the subcommand has to be baked into a no-arg binary. This wrapper
      # forwards xdph's only optional arg (--allow-token) through to the
      # subcommand. Region selection inside the picker still shells out to slurp
      # (mocha-themed via modules/packages/wayland/tools.nix).
      sharePicker = pkgs.writeShellScriptBin "wayle-share-picker" ''
        exec ${picker}/bin/wayle share-picker "$@"
      '';

      # Reference the wrapper by its STABLE profile path, not its /nix/store
      # path. profileDirectory is /home/stubbe/.nix-profile on standalone HM and
      # /etc/profiles/per-user/stubbe on NixOS — both constant across rebuilds
      # (only the symlink target moves). xdph caches this string at startup and
      # spawns the picker fresh per screenshare, so the cached path stays valid
      # across wayle bumps with no portal restart. xdph's user service has no
      # profile bin on PATH, hence the absolute path rather than a bare name.
      pickerBin = "${config.home.profileDirectory}/bin/wayle-share-picker";
    in
    lib.mkIf config.features.hyprland {
      home.packages = with pkgs; [
        hyprwire
        hyprland-protocols
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-wlr
        sharePicker
      ];

      xdg.configFile."hypr/xdph.conf".text = ''
        screencopy {
          custom_picker_binary = ${pickerBin}
        }
      '';
    };
}
