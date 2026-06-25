{ self, ... }:
{
  flake.modules.nixos.udev =
    { config, ... }:
    {
      # Source-of-truth: src/udev/rules.d/*.rules. The non-NixOS activation
      # script (setup-usb-autosuspend-disable.nix) installs the same
      # files into /etc/udev/rules.d/.
      services.udev.extraRules = ''
        ${builtins.readFile (self + "/src/udev/rules.d/90-usb-autosuspend-disable.rules")}
        ${builtins.readFile (self + "/src/udev/rules.d/90-usb-audio-power.rules")}
        ${builtins.readFile (self + "/src/udev/rules.d/90-touchpad-rebind.rules")}

        # Monitor-independent undock fallback. The DRM-hotplug rule above only
        # fires when a display connector changes, so undocking with no external
        # monitor attached never rebinds the wedged touchpad. The ThinkPad TB3
        # dock's thunderbolt device removal always fires on undock. SYSTEMD_WANTS
        # is ignored on "remove" events, so start the oneshot via RUN with an
        # absolute systemctl path (NixOS path here; the non-NixOS activation
        # installs the FHS-path equivalent). --no-block keeps the udev worker
        # from being held by the rebind's settle sleeps.
        ACTION=="remove", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", TEST=="/sys/bus/i2c/drivers/i2c_hid_acpi/i2c-SNSL0028:00", RUN+="${config.systemd.package}/bin/systemctl --no-block start touchpad-rebind.service"
      '';

      # Rebind the i2c-hid touchpad after a dock undock. See
      # src/udev/rules.d/90-touchpad-rebind.rules for the why. oneshot so
      # SYSTEMD_WANTS (DRM rule) or RUN systemctl (thunderbolt-remove fallback)
      # starts it once per event; the rebind script sleeps to let the dock power
      # transition settle, and runs here rather than in the udev worker so udev
      # isn't blocked. The same script is installed to /etc/udev/scripts on
      # non-NixOS by the matching privileged activation (setup-touchpad-rebind.nix).
      systemd.services.touchpad-rebind = {
        description = "Rebind wedged i2c-hid touchpad after dock undock";
        serviceConfig.Type = "oneshot";
        script = builtins.readFile (self + "/src/udev/scripts/rebind-touchpad.sh");
      };
    };
}
