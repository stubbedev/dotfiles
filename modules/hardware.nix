# Hardware: what the kernel needs to reach the disk, which firmware ships, and
# the udev rules that keep this particular laptop's peripherals sane.
#
# The udev rule FILES are the single source of truth (src/hardware/*.rules) and
# both halves below install the same bytes — NixOS through services.udev, and
# non-NixOS by writing them into /etc/udev/rules.d.
_: {
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
          # Broad initrd module set so the kernel can reach root on most
          # machines without a per-host hardware-configuration.nix. Covers
          # NVMe, SATA/AHCI, USB-attached storage, MMC/SD, and virtio (VMs /
          # disko-test runs). Without these the kernel cannot see the disk
          # controller in initrd and panics before mounting root.
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

          # Modern systemd-in-initrd: parallel mount setup, structured journal
          # during early boot, and a prerequisite for lanzaboote's stub
          # generation. Faster with better diagnostics than the legacy
          # script-based initrd.
          systemd.enable = true;
        };
        kernelModules = [
          "kvm-intel"
          "kvm-amd"
          "tun"
        ];

        # Wipe /tmp on every boot so stale build artefacts do not leak between
        # sessions.
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
        # Microcode + redistributable firmware. mkDefault on the cpu toggles so
        # a host can pin to a specific vendor; the default is "ship microcode
        # for whichever CPU we boot on".
        enableRedistributableFirmware = true;
        cpu = {
          intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
          amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
        };

        # i2c-dev module + udev rules so ddcutil works without sudo. The i2c
        # group is created automatically; modules/users.nix adds the user.
        i2c.enable = true;

        # logitech-udev-rules, so solaar can talk to the Unifying/Bolt
        # receiver's hidraw node without root. enableGraphical stays off: that
        # would add a second copy of solaar to systemPackages, and the app
        # itself ships from home-manager.
        logitech.wireless.enable = true;
      };

      # LVFS-backed firmware updates for UEFI/BIOS, SSDs, dock chips,
      # Thunderbolt controllers. Manual flow:
      #   sudo fwupdmgr refresh && sudo fwupdmgr get-updates && sudo fwupdmgr update
      services.fwupd.enable = true;

      # No periodic fstrim: btrfs mounts with discard=async by default since
      # kernel 6.2, so freed extents are already trimmed continuously. A weekly
      # full-FS `fstrim -a` over ~1.6T free on this DRAM-less SATA SSD (PNY
      # CS900) is redundant and pins the disk in D-state for 15+ min, starving
      # concurrent nix builds. Flip back on only for a filesystem without
      # async discard.
      services.fstrim.enable = false;

      # Newer brightnessctl uses the systemd-logind API instead of udev rules,
      # so the NixOS module was removed. Install the package directly.
      environment.systemPackages = [ pkgs.brightnessctl ];

      services.udev.extraRules = ''
        ${pkgs.stubbe.text "src/hardware/90-usb-autosuspend-disable.rules"}
        ${pkgs.stubbe.text "src/hardware/90-usb-audio-power.rules"}
        ${pkgs.stubbe.text "src/hardware/90-touchpad-rebind.rules"}

        # Monitor-independent undock fallback. The DRM-hotplug rule above only
        # fires when a display connector changes, so undocking with no external
        # monitor attached never rebinds the wedged touchpad. The ThinkPad TB3
        # dock's thunderbolt device removal always fires on undock.
        # SYSTEMD_WANTS is ignored on "remove" events, so start the oneshot via
        # RUN with an absolute systemctl path. --no-block keeps the udev worker
        # from being held by the rebind's settle sleeps.
        ACTION=="remove", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", TEST=="/sys/bus/i2c/drivers/i2c_hid_acpi/i2c-SNSL0028:00", RUN+="${lib.getExe' config.systemd.package "systemctl"} --no-block start touchpad-rebind.service"
      '';

      # Rebind the i2c-hid touchpad after a dock undock — see
      # src/hardware/90-touchpad-rebind.rules for why. oneshot, so either
      # trigger starts it once per event; the script sleeps to let the dock
      # power transition settle, and runs here rather than in the udev worker
      # so udev is not blocked.
      systemd.services.touchpad-rebind = {
        description = "Rebind wedged i2c-hid touchpad after dock undock";
        serviceConfig.Type = "oneshot";
        # socat: the script pokes Hyprland's request socket to reapply the
        # per-device scroll config after rebind.
        path = [ pkgs.socat ];
        script = pkgs.stubbe.text "src/hardware/rebind-touchpad.sh";
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

            ${pkgs.stubbe.installFile {
              source = pkgs.stubbe.file "src/hardware/90-usb-autosuspend-disable.rules";
              target = "/etc/udev/rules.d/90-usb-autosuspend-disable.rules";
            }}
            ${pkgs.stubbe.installFile {
              source = pkgs.stubbe.file "src/hardware/90-usb-audio-power.rules";
              target = "/etc/udev/rules.d/90-usb-audio-power.rules";
            }}

            # Apply the same policy to already-attached devices, since the rules
            # only fire on the next "add". Mirrors both rule files: HID (03) and
            # audio (01) get pinned on, everything else goes back to the kernel
            # default. An earlier version pinned every device on here, which
            # quietly undid autosuspend for the whole bus on every switch.
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
            # New rules apply on the next replug or reboot.
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
            ${pkgs.stubbe.installFile {
              source = pkgs.stubbe.file "src/hardware/90-touchpad-rebind.rules";
              target = "/etc/udev/rules.d/90-touchpad-rebind.rules";
            }}

            # Monitor-independent undock fallback, mirroring the
            # thunderbolt-remove rule in the NixOS half with the FHS systemctl
            # path. SYSTEMD_WANTS is ignored on "remove", so start via RUN.
            ${pkgs.stubbe.installText {
              name = "91-touchpad-rebind-thunderbolt.rules";
              target = "/etc/udev/rules.d/91-touchpad-rebind-thunderbolt.rules";
              text = ''
                ACTION=="remove", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", TEST=="/sys/bus/i2c/drivers/i2c_hid_acpi/i2c-SNSL0028:00", RUN+="/usr/bin/systemctl --no-block start touchpad-rebind.service"
              '';
            }}

            ${pkgs.stubbe.installFile {
              source = pkgs.stubbe.file "src/hardware/rebind-touchpad.sh";
              target = "/etc/udev/scripts/rebind-touchpad.sh";
              mode = "0755";
            }}

            # Event-triggered by SYSTEMD_WANTS from the udev DRM-hotplug rule,
            # so no [Install]/WantedBy — it must not be enabled into a target.
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

            # Reload rules so the next DRM hotplug picks them up. No trigger:
            # re-running events on an attached dock can wedge other devices.
            if command -v udevadm >/dev/null 2>&1; then
              sudo udevadm control --reload-rules >/dev/null 2>&1 || true
            fi
          '';
        };
      };
    };
}
