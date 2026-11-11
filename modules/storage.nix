_:
let
  cacheMaxAge = "30d";
in
{
  flake.modules.homeManager.storage =
    { config, lib, ... }:
    {
      systemd.user.tmpfiles.rules = lib.mkIf (config.host.platform != "android") [
        "e %C - - - ${cacheMaxAge}"
      ];
    };

  flake.modules.nixos.storage =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (config.stubbe) storage;

      subvolumeByMount = {
        "/" = "@";
        "/home" = "@home";
        "/nix" = "@nix";
        "/persist" = "@persist";
      }
      // lib.optionalAttrs (!config.host.impermanent) { "/var" = "@var"; }
      // lib.optionalAttrs (config.host.hibernateSwapSize != null) { "/swap" = "@swap"; };
    in
    {
      options.stubbe.storage = lib.mkOption {
        type = lib.types.attrs;
        readOnly = true;
        description = ''
          The installed disk layout, derived from the host flags: labels, the
          LUKS mapping, mount options and the subvolume per mount point.
          fileSystems, the impermanence rollback and stb-install-nixos (via
          `nix eval --json`) all read it, so the installer lays out exactly
          what the system mounts.
        '';
        default = rec {
          bootLabel = "STBBOOT";
          bootMountOptions = [
            "fmask=0077"
            "dmask=0077"
          ];
          btrfsLabel = "stubbe";
          btrfsDevice = "/dev/disk/by-label/${btrfsLabel}";
          dataPartLabel = "stubbe-data";
          luksName = if config.host.luks then "stubbe" else null;
          mountOptions = [
            "compress=zstd"
            "noatime"
          ];
          rootSubvolume = subvolumeByMount."/";
          blankSnapshot = "${rootSubvolume}-blank";
          subvolumes = lib.mapAttrsToList (mountpoint: subvolume: { inherit mountpoint subvolume; }) (
            lib.removeAttrs subvolumeByMount [ "/" ]
          );
        };
      };

      config = {
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

        boot.initrd.luks.devices = lib.mkIf (config.host.installed && storage.luksName != null) {
          ${storage.luksName} = {
            device = "/dev/disk/by-partlabel/${storage.dataPartLabel}";
            allowDiscards = true;
            bypassWorkqueues = true;
          };
        };

        fileSystems = lib.mkIf config.host.installed (
          lib.mapAttrs (_: subvol: {
            device = storage.btrfsDevice;
            fsType = "btrfs";
            options = storage.mountOptions ++ [ "subvol=${subvol}" ];
          }) subvolumeByMount
          // {
            "/boot" = {
              device = "/dev/disk/by-label/${storage.bootLabel}";
              fsType = "vfat";
              options = storage.bootMountOptions;
            };
          }
        );

        swapDevices = lib.mkIf (config.host.installed && config.host.hibernateSwapSize != null) [
          {
            device = "/swap/swapfile";
            size = config.host.hibernateSwapSize * 1024;
          }
        ];

        assertions = [
          {
            assertion = config.host.luks -> config.host.installed;
            message = "host.luks describes an installed disk layout; set host.installed too.";
          }
        ];
      };
    };
}
