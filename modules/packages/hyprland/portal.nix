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
      pickerBin = "${picker}/bin/wayle share-picker";
    in
    lib.mkIf config.features.hyprland {
      home.packages = with pkgs; [
        hyprwire
        hyprland-protocols
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-wlr
      ];

      # xdph resolves the picker by the absolute path in xdph.conf — its systemd
      # user service doesn't have the user profile bin on PATH, so a bare name
      # wouldn't resolve. xdph execs the value via /bin/sh -c, so the
      # `share-picker` argument is fine. Region selection inside the picker
      # still shells out to slurp (mocha-themed via
      # modules/packages/wayland/tools.nix). xdph caches this path at startup,
      # so the portal must restart when it moves — modules/home/systemd.nix
      # wires this file's store path into the xdph unit's X-Restart-Triggers so
      # sd-switch bounces the portal automatically on a wayle rebuild.
      xdg.configFile."hypr/xdph.conf".text = ''
        screencopy {
          custom_picker_binary = ${pickerBin}
        }
      '';
    };
}
