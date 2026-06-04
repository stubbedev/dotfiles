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
        ${builtins.readFile (self + "/src/udev/rules.d/90-touchpad-rebind.rules")}
      '';

      # Rebind the i2c-hid touchpad after the DRM hotplug fired by a dock
      # undock. See src/udev/rules.d/90-touchpad-rebind.rules for the why.
      # oneshot so SYSTEMD_WANTS starts it once per event; the rebind script
      # sleeps to let the dock power transition settle, and runs here rather
      # than in the udev worker so udev isn't blocked. The same script is
      # installed to /etc/udev/scripts on non-NixOS by the matching
      # privileged activation (setup-touchpad-rebind.nix).
      systemd.services.touchpad-rebind = {
        description = "Rebind wedged i2c-hid touchpad after dock undock";
        serviceConfig.Type = "oneshot";
        script = builtins.readFile (self + "/src/udev/scripts/rebind-touchpad.sh");
      };
    };
}
