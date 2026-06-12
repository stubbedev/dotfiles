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
      # bin/stb-install-nixos creates after `mkfs.btrfs` finishes. The
      # @persist subvol stores impermanence-survived state; on a non-
      # impermanent host it's still mounted (cheap) so the layout stays
      # forward-compatible when host.impermanent flips on.
      subvolumes = {
        "/" = "@";
        "/home" = "@home";
        "/nix" = "@nix";
        "/var" = "@var";
        "/persist" = "@persist";
      };

      mkSubvolMount = name: {
        device = btrfsDevice;
        fsType = "btrfs";
        options = mountOpts ++ [ "subvol=${name}" ];
      };
    in
    lib.mkIf config.host.installed {
      boot.supportedFilesystems = [ "btrfs" ];

      # Monthly checksum scrub catches bit-rot on the btrfs members
      # before silent corruption propagates to backups.
      services.btrfs.autoScrub = {
        enable = true;
        interval = "monthly";
        fileSystems = [ "/" ];
      };

      fileSystems = lib.mapAttrs (_: mkSubvolMount) subvolumes // {
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
