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

      # No earlyoom: its freeSwapThreshold is meaningless against zram (15G of
      # "free swap" is compressed RAM, not headroom) and it kills by RSS, so it
      # picks the biggest process — mysqld or a Chrome renderer — rather than
      # whatever is actually thrashing. systemd-oomd is PSI- and cgroup-aware
      # and is on by default; keep exactly one OOM killer.
      systemd.oomd.enable = true;

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

          Also tune the kernel for zram-backed swap and settle on one OOM killer:

            - vm.swappiness=150. The distro default (10) is disk-swap tuning and
              actively fights zram: it pins cold anon pages in real RAM when
              paging them out costs a zstd compress (~3.5:1 here) and no I/O.
            - vm.page-cluster=0. Swap readahead batches 8 pages per fault, which
              only pays off on a rotating seek. zram faults are single-page.
            - earlyoom masked, systemd-oomd left on. earlyoom's freeSwapThreshold
              cannot read zram (compressed "free swap" is not headroom) and it
              kills by RSS, so it reaches for mysqld or a Chrome renderer instead
              of whatever is thrashing. oomd is PSI- and cgroup-aware. Two OOM
              daemons with different policies is a race, so pick one.

          Without zram, the OOM path fires under load and SIGTERMs Chrome/Electron
          renderers (oom_score_adj +300) across every chromium-family app
          ("Aw, Snap!", blank Slack). zram gives ~3x effective headroom so the
          threshold is rarely hit.
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

          ${pkgs.stubbe.setup.text {
            name = "99-swap.conf";
            target = "/etc/sysctl.d/99-swap.conf";
            text = ''
              # managed-by: stubbe zram
              vm.swappiness = 150
              vm.page-cluster = 0
            '';
          }}

          sudo sysctl --system >/dev/null 2>&1 || true

          # One OOM killer. Mask rather than disable so an apt upgrade of the
          # earlyoom package cannot re-enable it behind our back.
          if systemctl list-unit-files earlyoom.service >/dev/null 2>&1; then
            sudo systemctl disable --now earlyoom.service >/dev/null 2>&1 || true
            sudo systemctl mask earlyoom.service >/dev/null 2>&1 || true
          fi
          sudo systemctl enable --now systemd-oomd.service >/dev/null 2>&1 || true

          ${pkgs.stubbe.setup.reloadUnits}
          sudo systemctl restart systemd-zram-setup@zram0.service
        '';
      };
    };
}
