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
          # machines without per-host hardware-configuration.nix. Covers
          # NVMe, SATA/AHCI, USB-attached storage, MMC/SD, and virtio
          # (VMs / disko-test runs). Without these, the kernel can't see
          # the disk controller in initrd and panics before mounting root.
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

          # Modern systemd-in-initrd: parallel mount setup, structured
          # journal during early boot, required prerequisite for
          # lanzaboote's stub generation. Faster + better diagnostics than
          # the legacy script-based initrd.
          systemd.enable = true;
        };
        kernelModules = [
          "kvm-intel"
          "kvm-amd"
          "tun"
        ];

        # Wipe /tmp on every boot so stale build artefacts don't leak
        # between sessions.
        tmp.cleanOnBoot = true;
      };

      hardware = {
        # Microcode + redistributable firmware. mkDefault on the cpu
        # toggles so a host can pin to a specific vendor if needed; the
        # default is "ship microcode for whichever CPU we boot on".
        enableRedistributableFirmware = true;
        cpu = {
          intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
          amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
        };

        # Load i2c-dev kernel module + udev rules so ddcutil works without sudo.
        # The i2c group is created automatically; users.nix adds the primary user.
        i2c.enable = true;
      };

      # SSDs benefit from periodic discard; the timer is cheap.
      services.fstrim.enable = true;

      # Newer brightnessctl uses systemd-logind API instead of udev rules,
      # so the NixOS module was removed. Install the package directly.
      environment.systemPackages = [ pkgs.brightnessctl ];
    };
}
