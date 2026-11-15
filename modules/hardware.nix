_:
let
  inotifyLimits = {
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
  };

  touchpadDriver = "/sys/bus/i2c/drivers/i2c_hid_acpi";
  touchpadDevice = "i2c-SNSL0028:00";
  touchpadRebindDescription = "Rebind wedged i2c-hid touchpad after dock undock";

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
    ACTION=="change", SUBSYSTEM=="drm", ENV{HOTPLUG}=="1", TEST=="${touchpadDriver}/${touchpadDevice}", ENV{SYSTEMD_WANTS}+="touchpad-rebind.service"
  '';

  touchpadUndockRule = systemctl: ''
    ACTION=="remove", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", TEST=="${touchpadDriver}/${touchpadDevice}", RUN+="${systemctl} --no-block start touchpad-rebind.service"
  '';

  rebindTouchpadScript = ''
    set -u

    drv=${touchpadDriver}
    dev=${touchpadDevice}

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

    for settle in 2 3 4 5; do
      sleep "$settle"
      echo "$dev" > "$drv/unbind" 2>/dev/null || true
      echo "$dev" > "$drv/bind"   2>/dev/null || true
      sleep 1
      mt_back && break
    done

    exit 0
  '';
in
{
  flake.modules.nixos.hardware =
    {
      config,
      lib,
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
        };
        kernelModules = [
          "kvm-intel"
          "kvm-amd"
          "tun"
        ];

        tmp.cleanOnBoot = true;

        # The 65536 default is exhausted by webpack-dev-server + octane --watch
        # over large node_modules trees → ENOSPC "file watchers reached".
        kernel.sysctl = inotifyLimits;
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
        ${touchpadUndockRule (lib.getExe' config.systemd.package "systemctl")}
      '';

      systemd.services.touchpad-rebind = {
        description = touchpadRebindDescription;
        serviceConfig.Type = "oneshot";
        script = rebindTouchpadScript;
      };
    };
}
