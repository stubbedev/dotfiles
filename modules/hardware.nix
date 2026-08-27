# Hardware: what the kernel needs to reach the disk, which firmware ships, and
# the udev rules that keep this particular laptop's peripherals sane.
#
# The udev rule TEXTS in the let below are the single source of truth and
# both halves install the same bytes — NixOS through services.udev, and
# non-NixOS by writing them into /etc/udev/rules.d.
_:
let
  usbAutosuspendRules = ''
    # HID only. This used to pin *every* USB device to power/control=on, which
    # also pinned the four xHCI root hubs and so kept their controllers out of
    # runtime suspend — the package can't reach its deep C-states with a USB
    # controller held awake, and that is real battery on an idle laptop.
    #
    # The reason for the rule was only ever input devices: a wireless receiver
    # coming out of autosuspend can swallow the keypress that woke it. So match
    # the HID class (03) in ID_USB_INTERFACES and leave everything else on the
    # kernel default. USB *audio* is pinned separately and for a different
    # reason (pops) by 90-usb-audio-power.rules.
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{ID_USB_INTERFACES}=="*:03*", TEST=="power/control", ATTR{power/control}="on"
  '';

  usbAudioPowerRules = ''
    # Disable USB power management for audio devices to prevent popping
    # This prevents USB audio devices from being auto-suspended, which can cause
    # audio pops, clicks, and dropouts especially with USB docks and KVM switches.

    # ThinkPad Thunderbolt 3 Dock Audio (17ef:306a) - device level only
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="17ef", ATTR{idProduct}=="306a", TEST=="power/control", ATTR{power/control}="on"
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="17ef", ATTR{idProduct}=="306a", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"

    # Generic rule: Disable autosuspend for all USB Audio devices (device level)
    # Only apply to actual USB devices, not interfaces
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{ID_USB_CLASS}=="01", TEST=="power/control", ATTR{power/control}="on"
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{ID_USB_CLASS}=="01", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
  '';

  touchpadRebindRules = ''
    # Lunar Lake (staggio) i2c-hid touchpad wedge on Thunderbolt dock unplug.
    #
    # After undocking, the SNSL0028:00 touchpad stays enumerated (visible in
    # `hyprctl devices`, `libinput list-devices`, /proc/bus/input/devices) but
    # emits zero input events. `hyprctl reload` cannot recover it because the
    # stall is in the i2c_hid_acpi driver, not the compositor; only rebinding
    # the driver (unbind + bind) brings the device back. Same class of power-
    # transition wedge as the SOF codec on this machine.
    #
    # The kernel emits a DRM HOTPLUG=1 uevent on every dock connector change,
    # which is the earliest root-context signal of the undock. Hand off to a
    # systemd oneshot via SYSTEMD_WANTS (not RUN+=) so the rebind — which sleeps
    # to let the dock power transition settle — runs outside the udev worker
    # instead of blocking it. TEST guards on the device node so the rule is a
    # no-op on any host without this touchpad.
    ACTION=="change", SUBSYSTEM=="drm", ENV{HOTPLUG}=="1", TEST=="/sys/bus/i2c/drivers/i2c_hid_acpi/i2c-SNSL0028:00", ENV{SYSTEMD_WANTS}+="touchpad-rebind.service"
  '';

  # Rebind the i2c-hid touchpad after a Thunderbolt dock undock. See
  # touchpadRebindRules above for the full why. Shared by both deploy paths:
  # NixOS runs it as systemd.services.touchpad-rebind's `script`; non-NixOS
  # installs it to /etc/udev/scripts/rebind-touchpad.sh, run by
  # /etc/systemd/system/touchpad-rebind.service. Both are pulled in by
  # SYSTEMD_WANTS from the udev DRM-hotplug rule.
  rebindTouchpadScript = ''
    set -u

    drv=/sys/bus/i2c/drivers/i2c_hid_acpi
    dev=i2c-SNSL0028:00

    # No-op on any host without this touchpad (the udev rule also guards, but
    # the service may be invoked directly).
    [ -e "$drv/$dev" ] || exit 0

    # True once the rebound device exposes multitouch. On probe the i2c-hid
    # driver sends a SET_REPORT to switch the device into touchpad (MT) mode;
    # that i2c transfer can fail silently while the dock power rail is still
    # unsettled, leaving the device in single-touch mode — the cursor moves but
    # two-finger scroll is dead. ABS_MT_POSITION_X (code 53) in the input node's
    # abs capability bitmask is the signal that MT mode actually took. The mask
    # prints as space-separated 64-bit words, most-significant first; codes < 64
    # (all the MT codes) live in the last (least-significant) word.
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

    # Re-apply Hyprland's per-device touchpad config to every live instance.
    # The unbind/bind above destroys and re-creates the input device, so the
    # per-device block in src/hyprland/hyprland.lua (scroll_method=2fg, natural_scroll,
    # ...) must be reapplied or two-finger scroll stays dead. scripts/monitor.toggle.sh
    # already reloads Hyprland on the undock DRM-hotplug, but that fires seconds
    # before this async rebind re-creates the device, and the no-monitor undock
    # (thunderbolt-remove fallback) never reaches that user-side reactor at all —
    # so the reload has to happen here, once MT is confirmed back.
    #
    # Talk to Hyprland's request socket directly instead of going through hyprctl:
    # the wire protocol is just the command string, and hyprctl is a home-manager
    # per-user binary that isn't on this root service's PATH. Root reaches the
    # user-owned socket via DAC_OVERRIDE. socat is on the service PATH (NixOS) or
    # the system (FHS); absent → the `|| true` degrades to before.
    reload_hypr() {
      local sock
      command -v socat >/dev/null 2>&1 || return 0
      for sock in /run/user/*/hypr/*/.socket.sock; do
        [ -S "$sock" ] || continue
        printf 'reload' | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1 || true
      done
    }

    # Rebind, then verify MT came back; retry with a growing settle if it didn't.
    # A single unbind/bind with a fixed sleep loses the race when the probe lands
    # before the bus settles. Worst case ~14s of sleeps, all in this background
    # oneshot — never blocks the udev worker.
    for settle in 2 3 4 5; do
      sleep "$settle"
      echo "$dev" > "$drv/unbind" 2>/dev/null || true
      echo "$dev" > "$drv/bind"   2>/dev/null || true
      sleep 1
      mt_back && break
    done

    # Reapply compositor scroll config now the device is back (even if the MT
    # verify never passed — a reload is cheap and idempotent).
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

      services.udev.extraRules = ''
        ${usbAutosuspendRules}
        ${usbAudioPowerRules}
        ${touchpadRebindRules}

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
      # touchpadRebindRules for why. oneshot, so either
      # trigger starts it once per event; the script sleeps to let the dock
      # power transition settle, and runs here rather than in the udev worker
      # so udev is not blocked.
      systemd.services.touchpad-rebind = {
        description = "Rebind wedged i2c-hid touchpad after dock undock";
        serviceConfig.Type = "oneshot";
        # socat: the script pokes Hyprland's request socket to reapply the
        # per-device scroll config after rebind.
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
            ${pkgs.stubbe.installText {
              name = "90-touchpad-rebind.rules";
              target = "/etc/udev/rules.d/90-touchpad-rebind.rules";
              text = touchpadRebindRules;
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

            ${pkgs.stubbe.installText {
              name = "rebind-touchpad.sh";
              target = "/etc/udev/scripts/rebind-touchpad.sh";
              mode = "0755";
              # env-resolved host bash, not a store path: this copy lives in
              # /etc and must survive a nix-collect-garbage.
              text = "#!/usr/bin/env bash\n" + rebindTouchpadScript;
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
