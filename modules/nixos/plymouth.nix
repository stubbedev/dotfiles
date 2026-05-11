_: {
  flake.modules.nixos.plymouth =
    { lib, pkgs, ... }:
    let
      # nixpkgs ships `catppuccin-plymouth` hardcoded to the macchiato
      # flavor. Upstream has all four — swap the sourceRoot and install
      # paths to package the mocha variant instead, matching the Kvantum
      # theme (Catppuccin-Mocha-Mauve, modules/theme/qt.nix).
      catppuccin-mocha-plymouth = pkgs.catppuccin-plymouth.overrideAttrs (_: {
        pname = "catppuccin-mocha-plymouth";
        sourceRoot = "source/themes/catppuccin-mocha";
        installPhase = ''
          runHook preInstall
          sed -i 's:\(^ImageDir=\)/usr:\1'"$out"':' catppuccin-mocha.plymouth
          mkdir -p $out/share/plymouth/themes/catppuccin-mocha
          cp * $out/share/plymouth/themes/catppuccin-mocha
          runHook postInstall
        '';
      });
    in
    {
      boot.plymouth = {
        enable = true;
        # `bgrt` was replaced because nvidia-drm.fbdev=1 + early-KMS
        # (modules/nixos/graphics.nix) takes over the framebuffer in
        # initrd before Plymouth can render the firmware BGRT logo —
        # result was a blank splash. catppuccin-mocha is self-contained
        # and uses the native panel resolution the early-KMS path opens.
        theme = "catppuccin-mocha";
        themePackages = [ catppuccin-mocha-plymouth ];
      };

      # Quiet kernel + low console log level keep the splash readable
      # instead of being shouted over by dmesg lines. udev / systemd
      # status messages still hit the journal.
      boot.kernelParams = [
        "quiet"
        "splash"
        "rd.systemd.show_status=auto"
        "rd.udev.log_level=3"
      ];
      boot.consoleLogLevel = lib.mkDefault 3;
      boot.initrd.verbose = false;
    };
}
