_: {
  flake.modules.nixos.hardware =
    { config, lib, ... }:
    {
      # Broad initrd module set so the kernel can reach root on most
      # machines without per-host hardware-configuration.nix. Covers
      # NVMe, SATA/AHCI, USB-attached storage, MMC/SD, and virtio
      # (VMs / disko-test runs). Without these, the kernel can't see
      # the disk controller in initrd and panics before mounting root.
      boot.initrd.availableKernelModules = [
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
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [
        "kvm-intel"
        "kvm-amd"
      ];

      # Microcode + redistributable firmware. mkDefault on the cpu
      # toggles so a host can pin to a specific vendor if needed; the
      # default is "ship microcode for whichever CPU we boot on".
      hardware.enableRedistributableFirmware = true;
      hardware.cpu.intel.updateMicrocode =
        lib.mkDefault config.hardware.enableRedistributableFirmware;
      hardware.cpu.amd.updateMicrocode =
        lib.mkDefault config.hardware.enableRedistributableFirmware;

      # SSDs benefit from periodic discard; the timer is cheap.
      services.fstrim.enable = true;
      # Wipe /tmp on every boot so stale build artefacts don't leak
      # between sessions.
      boot.tmp.cleanOnBoot = true;

      # Modern systemd-in-initrd: parallel mount setup, structured
      # journal during early boot, required prerequisite for
      # lanzaboote's stub generation. Faster + better diagnostics than
      # the legacy script-based initrd.
      boot.initrd.systemd.enable = true;

      # Udev rule so the primary user can adjust backlight without sudo.
      # Also installs the brightnessctl binary system-wide.
      hardware.brightnessctl.enable = true;

      # Load i2c-dev kernel module + udev rules so ddcutil works without sudo.
      # The i2c group is created automatically; users.nix adds the primary user.
      hardware.i2c.enable = true;
    };
}
