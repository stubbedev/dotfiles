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
      hyprland-preview-share-picker,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;

      # GTK4 + gtk4-layer-shell picker that replaces xdph's bundled Qt
      # `hyprland-share-picker`. gfxExe (not gfx): the buildRustPackage
      # output carries no meta.mainProgram, so name the binary explicitly;
      # gfxExe also nixGL-wraps it on non-NixOS so GTK4/EGL find their drivers.
      picker = homeLib.gfxExe "hyprland-preview-share-picker" (
        hyprland-preview-share-picker.packages.${system}.default
      );
      pickerBin = "${picker}/bin/hyprland-preview-share-picker";
    in
    lib.mkIf config.features.hyprland {
      home.packages = with pkgs; [
        hyprwire
        hyprland-protocols
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-wlr
        picker
      ];

      # Theme + layout for the picker are symlinked from src/ (config.yaml
      # points at the sibling style.css by relative path). xdph resolves the
      # picker by the absolute path in xdph.conf — its systemd user service
      # doesn't have the user profile bin on PATH, so a bare name wouldn't
      # resolve. Region selection inside the picker still shells out to slurp
      # (mocha-themed via modules/packages/wayland/tools.nix). Restart the
      # portal after changes: systemctl --user restart xdg-desktop-portal-hyprland
      xdg.configFile = homeLib.xdgSources [
        "hyprland-preview-share-picker/config.yaml"
        "hyprland-preview-share-picker/style.css"
      ]
      // {
        "hypr/xdph.conf".text = ''
          screencopy {
            custom_picker_binary = ${pickerBin}
          }
        '';
      };
    };
}
