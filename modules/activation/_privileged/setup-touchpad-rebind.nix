{ self, ... }:
{
  # NixOS deploys this via modules/nixos/udev.nix (udev rule + systemd
  # service). This activation is the non-NixOS counterpart and is gated off
  # on NixOS by mkSudoSetupModule (host.platform != "nixos").
  enableIf = { config, ... }: config.features.desktop;
  args =
    { lib, homeLib, ... }:
    let
      # Event-triggered by SYSTEMD_WANTS from the udev DRM-hotplug rule, so
      # no [Install]/WantedBy — it must not be enabled into a target.
      unit = {
        Unit = {
          Description = "Rebind wedged i2c-hid touchpad after dock undock";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "/etc/udev/scripts/rebind-touchpad.sh";
        };
      };
    in
    homeLib.mkInstallPrompt {
      subject = "touchpad dock-unplug rebind rule";
      body = ''
        On a Thunderbolt dock undock the i2c-hid touchpad stops emitting
        events until its driver is rebound. This installs a udev rule that
        rebinds it automatically on the DRM hotplug, plus the helper script
        and systemd service it triggers.
      '';
      actionScript = ''
        sudo install -d -m 0755 /etc/udev/rules.d /etc/udev/scripts

        ${homeLib.installSystemFile {
          target = "/etc/udev/rules.d/90-touchpad-rebind.rules";
          content = builtins.readFile (self + "/src/udev/rules.d/90-touchpad-rebind.rules");
        }}

        ${homeLib.installSystemFile {
          target = "/etc/udev/scripts/rebind-touchpad.sh";
          mode = "0755";
          content = builtins.readFile (self + "/src/udev/scripts/rebind-touchpad.sh");
        }}

        ${homeLib.installSystemFile {
          target = "/etc/systemd/system/touchpad-rebind.service";
          content = lib.generators.toINI { listsAsDuplicateKeys = true; } unit;
        }}

        sudo systemctl daemon-reload

        # Reload rules so the next DRM hotplug picks them up. No trigger:
        # re-running events on an attached dock can wedge other devices.
        if command -v udevadm >/dev/null 2>&1; then
          sudo udevadm control --reload-rules >/dev/null 2>&1 || true
        fi
      '';
    };
}
