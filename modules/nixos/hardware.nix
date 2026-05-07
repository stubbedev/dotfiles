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
    };
}
