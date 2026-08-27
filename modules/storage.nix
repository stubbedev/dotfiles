# Storage: the btrfs layout, swap, SMART monitoring, removable media, and the
# stateless-root option.
_: {
  flake.modules.nixos.storage =
    {
      config,
      lib,
      ...
    }:
    let
      # The installer formats every selected disk as one btrfs volume labeled
      # `stubbe`. Any member device is enough to mount it; btrfs auto-discovers
      # the rest via `btrfs device scan` at boot when boot.supportedFilesystems
      # contains "btrfs".
      btrfsDevice = "/dev/disk/by-label/stubbe";
      mountOpts = [
        "compress=zstd"
        "noatime"
      ];

      # Mountpoint → subvolume. Keep in lockstep with what bin/stb-install-nixos
      # creates after `mkfs.btrfs` finishes. @persist stores
      # impermanence-survived state; on a non-impermanent host it is still
      # mounted (cheap) so the layout stays forward-compatible when
      # host.impermanent flips on.
      subvolumes = {
        "/" = "@";
        "/home" = "@home";
        "/nix" = "@nix";
        "/var" = "@var";
        "/persist" = "@persist";
      };
    in
    {
      # Compressed RAM swap — no disk cost, kicks in under memory pressure and
      # keeps the OOM killer at bay during big rebuilds. zstd compresses ~3x on
      # typical workloads, so 50% of RAM ≈ 1.5x extra effective. The non-NixOS
      # half is the zram setup below.
      zramSwap = {
        enable = true;
        algorithm = "zstd";
        memoryPercent = 50;
      };

      services = {
        # Userspace OOM killer that fires before the kernel's last-resort
        # heuristic: it picks a smarter victim (highest oom_score under memory
        # pressure, not a random root process) and reacts at lower thresholds.
        # With zram in place true OOM is rare, but this keeps response time
        # predictable when it hits. Defaults are 10/10; tightened because zram
        # compresses ~3x, so 10% nominal swap ≈ 30% effective.
        earlyoom = {
          enable = true;
          freeMemThreshold = 5;
          freeSwapThreshold = 10;
        };

        # SMART monitoring: polls every disk on a timer and logs failing
        # attributes. No email destination — `journalctl -u smartd` surfaces
        # alerts. autodetect picks up every /dev/sd*, /dev/nvme* with no
        # per-host config.
        smartd = {
          enable = true;
          autodetect = true;
          notifications.x11.enable = true;
        };

        # Auto-mount removable media (USB sticks, SD cards, MTP). The shell's
        # disk widget and the file managers read its D-Bus API.
        udisks2.enable = true;

        # Virtual filesystem layer for GIO apps (PCManFM, nautilus, …): trash
        # support, MTP device mounting, SFTP/SMB browsing, archive mounting.
        # Without it, deleting in PCManFM is permanent and network/phone mounts
        # fail silently.
        gvfs.enable = true;

        # Monthly checksum scrub catches bit-rot on the btrfs members before
        # silent corruption propagates to backups.
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
    { lib, pkgs, ... }:
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
        # Reinstall if the package is removed: the generator binary appearing or
        # disappearing flips the lock so this re-runs.
        stateInputs = [ "/usr/lib/systemd/system-generators/zram-generator" ];
        preCheck = pkgs.stubbe.requireCommand "systemctl";
        script = ''
          # Activations run with a stripped PATH; restore it so `command -v`
          # finds apt-get / dnf / pacman under /usr/sbin etc.
          PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

          # systemd-zram-generator ships only a systemd generator (no PATH
          # binary), so installHostPackage's `command -v` detection cannot see
          # it — gate on the generator file instead. The package name differs:
          # Debian/Ubuntu call it systemd-zram-generator, Fedora/Arch
          # zram-generator.
          if [ ! -e /usr/lib/systemd/system-generators/zram-generator ] \
             && [ ! -e /lib/systemd/system-generators/zram-generator ]; then
            if command -v apt-get >/dev/null 2>&1; then
              sudo apt-get update
              sudo apt-get install -y --no-install-recommends systemd-zram-generator
            elif command -v dnf >/dev/null 2>&1; then
              sudo dnf install -y --setopt=install_weak_deps=False zram-generator
            elif command -v pacman >/dev/null 2>&1; then
              sudo pacman -S --needed --noconfirm zram-generator
            else
              echo "No supported package manager (apt-get/dnf/pacman) found." >&2
              exit 1
            fi
          fi

          # Mirrors zramSwap in the NixOS half: zstd, 50% of RAM.
          ${pkgs.stubbe.installText {
            name = "zram-generator.conf";
            target = "/etc/systemd/zram-generator.conf";
            text =
              "# managed-by: stubbe zram\n"
              + lib.generators.toINI { } {
                zram0 = {
                  zram-size = "ram / 2";
                  compression-algorithm = "zstd";
                };
              };
          }}

          # daemon-reload re-runs the generator against the new conf (creating
          # the systemd-zram-setup@zram0 instance); restart applies it live so
          # the device comes up without a reboot.
          sudo systemctl daemon-reload
          sudo systemctl restart systemd-zram-setup@zram0.service
        '';
      };
    };
}
