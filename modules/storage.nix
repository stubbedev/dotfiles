_: {
  flake.modules.nixos.storage =
    {
      config,
      lib,
      ...
    }:
    let
      btrfsDevice = "/dev/disk/by-label/stubbe";
      mountOpts = [
        "compress=zstd"
        "noatime"
      ];

      subvolumes = {
        "/" = "@";
        "/home" = "@home";
        "/nix" = "@nix";
        "/var" = "@var";
        "/persist" = "@persist";
      };
    in
    {
      services = {
        smartd = {
          enable = true;
          autodetect = true;
          notifications.x11.enable = true;
        };

        udisks2.enable = true;

        gvfs.enable = true;

        btrfs.autoScrub = lib.mkIf config.host.installed {
          enable = true;
          interval = "monthly";
          fileSystems = [ "/" ];
        };
      };

      boot.supportedFilesystems = lib.mkIf config.host.installed [ "btrfs" ];

      fileSystems = lib.mkIf config.host.installed (
        lib.mapAttrs (_: subvol: {
          device = btrfsDevice;
          fsType = "btrfs";
          options = mountOpts ++ [ "subvol=${subvol}" ];
        }) subvolumes
        // {
          "/boot" = {
            device = "/dev/disk/by-label/STBBOOT";
            fsType = "vfat";
            options = [
              "fmask=0077"
              "dmask=0077"
            ];
          };
        }
      );
    };
}
