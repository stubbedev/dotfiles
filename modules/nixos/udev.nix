{ self, ... }:
{
  flake.modules.nixos.udev =
    { ... }:
    {
      # Source-of-truth: src/udev/rules.d/*.rules. The non-NixOS activation
      # script (setup-usb-autosuspend-disable.nix) installs the same
      # files into /etc/udev/rules.d/.
      services.udev.extraRules = ''
        # managed-by: nixos usb-autosuspend-disable
        ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"

        ${builtins.readFile (self + "/src/udev/rules.d/90-usb-audio-power.rules")}
      '';
    };
}
