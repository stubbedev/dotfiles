{ self, ... }:
{
  flake.modules.nixos.plymouth =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      boot = {
        plymouth = {
          enable = true;
          package = pkgs.plymouth.override { systemd = config.boot.initrd.systemd.package; };
          theme = "catppuccin-mocha";
          themePackages = [ pkgs.catppuccin-mocha-plymouth ];
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
