_: {
  flake.modules.nixos.filesystems =
    { config, lib, ... }:
    let
      # The installer formats every selected disk as one btrfs volume
      # labeled `stubbe`. Any of the member devices is enough to mount the
      # filesystem; btrfs auto-discovers the rest via `btrfs device scan`
      # at boot when boot.supportedFilesystems contains "btrfs".
      btrfsDevice = "/dev/disk/by-label/stubbe";
      mountOpts = [
        "compress=zstd"
        "noatime"
      ];

      # Subvolume name → mountpoint. Keep this list in lockstep with what
      # bin/stb-install-nixos creates after `mkfs.btrfs` finishes.
      subvolumes = {
        "/" = "@";
        "/home" = "@home";
        "/nix" = "@nix";
        "/var" = "@var";
        "/.snapshots" = "@snapshots";
      };

      mkSubvolMount = name: {
        device = btrfsDevice;
        fsType = "btrfs";
        options = mountOpts ++ [ "subvol=${name}" ];
      };
    in
    lib.mkIf config.host.installed {
      boot.supportedFilesystems = [ "btrfs" ];

      fileSystems = lib.mapAttrs (_: subvol: mkSubvolMount subvol) subvolumes // {
        "/boot" = {
          device = "/dev/disk/by-label/STBBOOT";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
      };
    };
}
