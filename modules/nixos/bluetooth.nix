_: {
  flake.modules.nixos.bluetooth =
    { ... }:
    {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };

      # GUI manager (replaces the `blueman` entry from the non-NixOS
      # modules/packages/system.nix path). On NixOS we want the system
      # service so the tray applet finds an autostart-ready daemon.
      services.blueman.enable = true;
    };
}
