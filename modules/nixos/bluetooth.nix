_: {
  flake.modules.nixos.bluetooth = _: {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      # Battery reporting on BLE peripherals (mice, headphones,
      # controllers) via the standard BAS GATT characteristic.
      settings.General.Experimental = true;
    };

    # GUI manager (replaces the `blueman` entry from the non-NixOS
    # modules/packages/system.nix path). On NixOS we want the system
    # service so the tray applet finds an autostart-ready daemon.
    services.blueman.enable = true;
  };
}
