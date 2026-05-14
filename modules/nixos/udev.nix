{ self, ... }:
{
  flake.modules.nixos.udev =
    { ... }:
    {
      # Source-of-truth: src/udev/rules.d/*.rules. The non-NixOS activation
      # script (setup-usb-autosuspend-disable.nix) installs the same
      # files into /etc/udev/rules.d/.
      services.udev.extraRules = ''
        ${builtins.readFile (self + "/src/udev/rules.d/90-usb-autosuspend-disable.rules")}
        ${builtins.readFile (self + "/src/udev/rules.d/90-usb-audio-power.rules")}
      '';
    };
}
