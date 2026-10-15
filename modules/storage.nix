_:
let
  memorySysctl = {
    "vm.swappiness" = 150;
    "vm.page-cluster" = 0;
    "kernel.sysrq" = 240;
  };

  oomdMemoryPressure = {
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "80%";
  };

  oomdSlices = {
    "-" = oomdMemoryPressure // {
      ManagedOOMSwap = "kill";
    };
    system = oomdMemoryPressure;
    user = oomdMemoryPressure;
  };

  oomdUserSlice = {
    Slice = oomdMemoryPressure;
  };
in
{
  flake.modules.nixos.storage =
    {
      config,
      lib,
      pkgs,
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

      systemd = {
        oomd.enable = true;
        slices = lib.mapAttrs (_: sliceConfig: { inherit sliceConfig; }) oomdSlices;
        user.units.slice = {
          text = pkgs.stubbe.gen.unitText oomdUserSlice;
          overrideStrategy = "asDropin";
        };
      };

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

      boot = {
        kernel.sysctl = memorySysctl;
        supportedFilesystems = lib.mkIf config.host.installed [ "btrfs" ];
      };

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
    { lib, pkgs, ... }:
    let
      oomdDropin =
        {
          name,
          target,
          unit,
        }:
        pkgs.stubbe.setup.text {
          inherit name target;
          text = pkgs.stubbe.managedBy "oomd" + pkgs.stubbe.gen.unitText unit;
        };
    in
    {
      stubbe.setup.memory = {
        privileged = true;
        title = "Installing zram swap and the OOM policy";
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
            - kernel.sysrq=240. Sync, remount, signal and reboot keys, so
              Alt+SysRq+F runs the kernel OOM killer on a frozen desktop instead
              of a forced power-off.
            - earlyoom masked, systemd-oomd on. earlyoom's freeSwapThreshold
              cannot read zram (compressed "free swap" is not headroom) and it
              kills by RSS, so it reaches for mysqld or a Chrome renderer instead
              of whatever is thrashing. oomd is PSI- and cgroup-aware. Two OOM
              daemons with different policies is a race, so pick one.
            - oomd slice drop-ins. oomd only acts on cgroups that opt in, so
              without them it runs and never kills: the root, system and user
              slices kill on sustained memory pressure, and the root slice also
              kills the biggest swap user once zram is nearly full.
        '';
        stateInputs = [ "/usr/lib/systemd/system-generators/zram-generator" ];
        preCheck = pkgs.stubbe.setup.requireCommand "systemctl";
        script = ''
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
            name = "99-memory.conf";
            target = "/etc/sysctl.d/99-memory.conf";
            text =
              pkgs.stubbe.managedBy "memory"
              + lib.generators.toKeyValue {
                mkKeyValue = lib.generators.mkKeyValueDefault { } " = ";
              } memorySysctl;
          }}
          sudo rm -f /etc/sysctl.d/99-swap.conf

          sudo sysctl --system >/dev/null 2>&1 || true

          ${lib.concatStrings (
            lib.mapAttrsToList (
              slice: sliceConfig:
              oomdDropin {
                name = "oomd-${slice}.slice.conf";
                target = "/etc/systemd/system/${slice}.slice.d/10-stubbe-oomd.conf";
                unit.Slice = sliceConfig;
              }
            ) oomdSlices
          )}
          ${oomdDropin {
            name = "oomd-user-slices.conf";
            target = "/etc/systemd/user/slice.d/10-stubbe-oomd.conf";
            unit = oomdUserSlice;
          }}

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
