_:
let
  usbAutosuspendRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{ID_USB_INTERFACES}=="*:03*", TEST=="power/control", ATTR{power/control}="on"
  '';

  usbAudioPowerRules = ''

    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="17ef", ATTR{idProduct}=="306a", TEST=="power/control", ATTR{power/control}="on"
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="17ef", ATTR{idProduct}=="306a", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"

    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{ID_USB_CLASS}=="01", TEST=="power/control", ATTR{power/control}="on"
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{ID_USB_CLASS}=="01", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
  '';

  touchpadRebindRules = ''
    ACTION=="change", SUBSYSTEM=="drm", ENV{HOTPLUG}=="1", TEST=="/sys/bus/i2c/drivers/i2c_hid_acpi/i2c-SNSL0028:00", ENV{SYSTEMD_WANTS}+="touchpad-rebind.service"
  '';

  rebindTouchpadScript = ''
    set -u

    drv=/sys/bus/i2c/drivers/i2c_hid_acpi
    dev=i2c-SNSL0028:00

    [ -e "$drv/$dev" ] || exit 0

    mt_back() {
      local f abs
      for f in "$drv/$dev"/*/input/input*/capabilities/abs; do
        [ -r "$f" ] || continue
        abs=$(awk '{print $NF}' "$f")
        [ -n "$abs" ] || continue
        if (( 0x$abs & (1 << 53) )); then return 0; fi
      done
      return 1
    }

    reload_hypr() {
      local sock
      command -v socat >/dev/null 2>&1 || return 0
      for sock in /run/user/*/hypr/*/.socket.sock; do
        [ -S "$sock" ] || continue
        printf 'reload' | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1 || true
      done
    }

    for settle in 2 3 4 5; do
      sleep "$settle"
      echo "$dev" > "$drv/unbind" 2>/dev/null || true
      echo "$dev" > "$drv/bind"   2>/dev/null || true
      sleep 1
      mt_back && break
    done

    reload_hypr
    exit 0
  '';
in
{
  flake.modules.nixos.hardware =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      boot = {
        initrd = {
          availableKernelModules = [
            "nvme"
            "ahci"
            "xhci_pci"
            "ehci_pci"
            "usbhid"
            "usb_storage"
            "sd_mod"
            "sr_mod"
            "rtsx_pci_sdmmc"
            "virtio_pci"
            "virtio_blk"
            "virtio_scsi"
          ];
          kernelModules = [ ];

          systemd.enable = true;
        };
        kernelModules = [
          "kvm-intel"
          "kvm-amd"
          "tun"
        ];

        tmp.cleanOnBoot = true;

        # The 65536 default is exhausted by webpack-dev-server + octane --watch
        # over large node_modules trees → ENOSPC "file watchers reached". The
        # non-NixOS half is the inotifyLimits setup below.
        kernel.sysctl = {
          "fs.inotify.max_user_watches" = 524288;
          "fs.inotify.max_user_instances" = 512;
        };
      };

      hardware = {
        enableRedistributableFirmware = true;
        cpu = {
          intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
          amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
        };

        i2c.enable = true;

        # solaar needs these rules to reach the receiver hidraw node without
        # root. enableGraphical stays off: it would add a second copy of solaar,
        # which already ships from home-manager.
        logitech.wireless.enable = true;
      };

      services.fwupd.enable = true;

      # No periodic fstrim: btrfs mounts discard=async since kernel 6.2, so
      # freed extents are already trimmed continuously.
      services.fstrim.enable = false;

      services.udev.extraRules = ''
        ${usbAutosuspendRules}
        ${usbAudioPowerRules}
        ${touchpadRebindRules}

        ACTION=="remove", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", TEST=="/sys/bus/i2c/drivers/i2c_hid_acpi/i2c-SNSL0028:00", RUN+="${lib.getExe' config.systemd.package "systemctl"} --no-block start touchpad-rebind.service"
      '';

      systemd.services.touchpad-rebind = {
        description = "Rebind wedged i2c-hid touchpad after dock undock";
        serviceConfig.Type = "oneshot";
        path = [ pkgs.socat ];
        script = rebindTouchpadScript;
      };
    };

  flake.modules.homeManager.hardware =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      stubbe.setup = {
        inotifyLimits = {
          privileged = true;
          title = "Installing inotify watch/instance limits";
          body = ''
            Raises fs.inotify.max_user_watches and max_user_instances. The 65536
            default is exhausted by webpack-dev-server + octane --watch over large
            node_modules trees, causing ENOSPC "file watchers reached" errors.
          '';
          script = ''
            ${pkgs.stubbe.installText {
              name = "60-inotify-limits.conf";
              target = "/etc/sysctl.d/60-inotify-limits.conf";
              text = ''
                # managed-by: stubbe inotify-limits
                fs.inotify.max_user_watches = 524288
                fs.inotify.max_user_instances = 512
              '';
            }}

            if command -v sysctl >/dev/null 2>&1; then
              sudo sysctl --system >/dev/null 2>&1 || true
            fi
          '';
        };

        usbPower = lib.mkIf config.features.desktop {
          privileged = true;
          title = "Installing USB power management rules";
          body = ''
            This pins USB input devices (HID) and USB audio devices to full
            power, so a wireless receiver never swallows the keypress that woke
            it and audio devices never pop on resume. Everything else — hubs,
            camera, the xHCI root hubs — keeps the kernel's autosuspend default,
            which is what lets the USB controllers reach their low-power states.
          '';
          script = ''
            PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

            ${pkgs.stubbe.installText {
              name = "90-usb-autosuspend-disable.rules";
              target = "/etc/udev/rules.d/90-usb-autosuspend-disable.rules";
              text = usbAutosuspendRules;
            }}
            ${pkgs.stubbe.installText {
              name = "90-usb-audio-power.rules";
              target = "/etc/udev/rules.d/90-usb-audio-power.rules";
              text = usbAudioPowerRules;
            }}

            for dev in /sys/bus/usb/devices/*; do
              [ -w "$dev/power/control" ] || continue
              case "$(udevadm info --query=property --property=ID_USB_INTERFACES --value "$dev" 2>/dev/null)" in
              *:03* | *:01*) printf 'on' | sudo tee "$dev/power/control" >/dev/null ;;
              *) printf 'auto' | sudo tee "$dev/power/control" >/dev/null ;;
              esac
            done

            if command -v udevadm >/dev/null 2>&1; then
              sudo udevadm control --reload-rules >/dev/null 2>&1 || true
            fi
          '';
        };

        touchpadRebind = lib.mkIf config.features.desktop {
          privileged = true;
          title = "Installing touchpad dock-unplug rebind rule";
          body = ''
            On a Thunderbolt dock undock the i2c-hid touchpad stops emitting
            events until its driver is rebound. This installs udev rules that
            rebind it automatically — on the DRM hotplug, and (for undocks with
            no external monitor) on the dock's thunderbolt device removal — plus
            the helper script and systemd service they trigger.
          '';
          script = ''
            ${pkgs.stubbe.installText {
              name = "90-touchpad-rebind.rules";
              target = "/etc/udev/rules.d/90-touchpad-rebind.rules";
              text = touchpadRebindRules;
            }}

            ${pkgs.stubbe.installText {
              name = "91-touchpad-rebind-thunderbolt.rules";
              target = "/etc/udev/rules.d/91-touchpad-rebind-thunderbolt.rules";
              text = ''
                ACTION=="remove", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", TEST=="/sys/bus/i2c/drivers/i2c_hid_acpi/i2c-SNSL0028:00", RUN+="/usr/bin/systemctl --no-block start touchpad-rebind.service"
              '';
            }}

            ${pkgs.stubbe.installText {
              name = "rebind-touchpad.sh";
              target = "/etc/udev/scripts/rebind-touchpad.sh";
              mode = "0755";
              text = "#!/usr/bin/env bash\n" + rebindTouchpadScript;
            }}

            ${pkgs.stubbe.installText {
              name = "touchpad-rebind.service";
              target = "/etc/systemd/system/touchpad-rebind.service";
              text = lib.generators.toINI { listsAsDuplicateKeys = true; } {
                Unit.Description = "Rebind wedged i2c-hid touchpad after dock undock";
                Service = {
                  Type = "oneshot";
                  ExecStart = "/etc/udev/scripts/rebind-touchpad.sh";
                };
              };
            }}

            sudo systemctl daemon-reload

            if command -v udevadm >/dev/null 2>&1; then
              sudo udevadm control --reload-rules >/dev/null 2>&1 || true
            fi
          '';
        };
      };
    };
}
