{ self, ... }:
{
  flake.modules.nixos.plymouth =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      # Shared with modules/activation/_privileged/setup-plymouth-theme.nix.
      inherit (import (self + "/lib/plymouth.nix") { inherit pkgs; })
        catppuccinMochaPlymouth
        ;
    in
    {
      boot = {
        plymouth = {
          enable = true;
          package = pkgs.plymouth.override { systemd = config.boot.initrd.systemd.package; };
          theme = "catppuccin-mocha";
          themePackages = [ catppuccinMochaPlymouth ];
        };

        # Quiet kernel + low console log level keep the splash readable
        # instead of being shouted over by dmesg lines. udev / systemd
        # status messages still hit the journal.
        kernelParams = [
          "quiet"
          "splash"
          "rd.systemd.show_status=auto"
          "rd.udev.log_level=3"
        ];
        consoleLogLevel = lib.mkDefault 3;
        initrd.verbose = false;
      };
    };
}
