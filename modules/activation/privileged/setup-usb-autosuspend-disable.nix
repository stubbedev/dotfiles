{ self, ... }:

{
  flake.modules.homeManager.setupUsbAutosuspendDisable =
    (import ../../../lib/activation-setups.nix).mkSudoSetupModule
      (
        {
          name = "setupUsbAutosuspendDisable";
        }
        // {
          enableIf = { config, ... }: config.features.desktop;
          args =
            { homeLib, ... }:
            homeLib.mkInstallPrompt {
              subject = "USB power management rules";
              body = ''
                This pins USB input devices (HID) and USB audio devices to full
                power, so a wireless receiver never swallows the keypress that woke
                it and audio devices never pop on resume. Everything else — hubs,
                camera, the xHCI root hubs — keeps the kernel's autosuspend default,
                which is what lets the USB controllers reach their low-power states.
              '';
              actionScript = ''
                # Activations run with a stripped PATH; restore it so udevadm is
                # found under /usr/sbin etc.
                PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

                sudo install -d -m 0755 /etc/udev/rules.d

                ${homeLib.installSystemFile {
                  target = "/etc/udev/rules.d/90-usb-autosuspend-disable.rules";
                  content = builtins.readFile (self + "/src/udev/rules.d/90-usb-autosuspend-disable.rules");
                }}

                ${homeLib.installSystemFile {
                  target = "/etc/udev/rules.d/90-usb-audio-power.rules";
                  content = builtins.readFile (self + "/src/udev/rules.d/90-usb-audio-power.rules");
                }}

                # Apply the same policy to devices already attached, since the rules
                # above only fire on the next "add". Mirrors both rule files: HID (03)
                # and audio (01) get pinned on, everything else goes back to the
                # kernel default. An earlier version pinned every device on here,
                # which quietly undid autosuspend for the whole bus on every switch.
                for dev in /sys/bus/usb/devices/*; do
                  [ -w "$dev/power/control" ] || continue
                  case "$(udevadm info --query=property --property=ID_USB_INTERFACES --value "$dev" 2>/dev/null)" in
                  *:03* | *:01*) printf 'on' | sudo tee "$dev/power/control" >/dev/null ;;
                  *) printf 'auto' | sudo tee "$dev/power/control" >/dev/null ;;
                  esac
                done

                # Reload rules so new plug events pick them up. Do NOT re-trigger
                # add events on already-attached devices: that re-enumerates the
                # Thunderbolt dock and can wedge the HDA codec's DP audio MUX
                # (kernel ELD valid, codec ELDV=0, MUX stuck on a phantom Dev).
                # New rules apply automatically on next replug or reboot.
                if command -v udevadm >/dev/null 2>&1; then
                  sudo udevadm control --reload-rules >/dev/null 2>&1 || true
                fi
              '';
            };
        }
      );
}
