_: {
  flake.modules.nixos.plymouth =
    { lib, ... }:
    {
      boot.plymouth = {
        enable = true;
        # `bgrt` reuses the EFI vendor logo from firmware. No graphics
        # asset to ship; integrates nicely with systemd-boot / lanzaboote.
        theme = "bgrt";
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
