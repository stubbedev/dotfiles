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
      zramSwap = {
        enable = true;
        algorithm = "zstd";
        memoryPercent = 50;
      };

      services = {
        earlyoom = {
          enable = true;
          freeMemThreshold = 5;
          freeSwapThreshold = 10;
        };

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

  flake.modules.homeManager.storage =
    { pkgs, ... }:
    {
      stubbe.setup.zram = {
        privileged = true;
        title = "Installing zram compressed swap";
        body = ''
          Install systemd-zram-generator, write a managed
          /etc/systemd/zram-generator.conf (zstd, size = RAM/2), and bring up the
          systemd-zram-setup@zram0 service so a compressed RAM swap device
          absorbs memory pressure before the disk swapfile fills.

          Without it, earlyoom fires under load and SIGTERMs Chrome/Electron
          renderers (oom_score_adj +300) across every chromium-family app
          ("Aw, Snap!", blank Slack). zram gives ~3x effective headroom so the
          OOM threshold is rarely hit.
        '';
        stateInputs = [ "/usr/lib/systemd/system-generators/zram-generator" ];
        preCheck = pkgs.stubbe.setup.requireCommand "systemctl";
        script = ''
          PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

          ${pkgs.stubbe.setup.hostPackage {
            have = "[ -e /usr/lib/systemd/system-generators/zram-generator ] || [ -e /lib/systemd/system-generators/zram-generator ]";
            apt = [ "systemd-zram-generator" ];
            dnf = [ "zram-generator" ];
            pacman = [ "zram-generator" ];
          }}

          ${pkgs.stubbe.setup.text {
            name = "zram-generator.conf";
            target = "/etc/systemd/zram-generator.conf";
            text =
              pkgs.stubbe.managedBy "zram"
              + pkgs.stubbe.gen.iniText {
                zram0 = {
                  zram-size = "ram / 2";
                  compression-algorithm = "zstd";
                };
              };
          }}

          ${pkgs.stubbe.setup.reloadUnits}
          sudo systemctl restart systemd-zram-setup@zram0.service
        '';
      };
    };
}
