_:
let
  memorySysctl = {
    "vm.swappiness" = 150;
    "vm.page-cluster" = 0;
    "kernel.sysrq" = 240;
  };

  thrashingTmpfiles = "w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 1000";

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

  oomKillMessages = {
    d989611b15e44c9dbf31e3c81256e4ed = "systemd-oomd";
    fe6faa94e7774663a0da52717891d8ef = "the kernel OOM killer";
  };
in
{
  flake.modules.nixos.memory =
    { lib, pkgs, ... }:
    {
      zramSwap = {
        enable = true;
        algorithm = "zstd";
        memoryPercent = 50;
      };

      boot.kernel.sysctl = memorySysctl;

      systemd = {
        tmpfiles.rules = [ thrashingTmpfiles ];
        oomd.enable = true;
        slices = lib.mapAttrs (_: sliceConfig: { inherit sliceConfig; }) oomdSlices;
        user.units.slice = {
          text = pkgs.stubbe.gen.unitText oomdUserSlice;
          overrideStrategy = "asDropin";
        };
      };
    };

  flake.modules.homeManager.memory =
    {
      config,
      lib,
      pkgs,
      ...
    }:
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

      oomNotify = pkgs.stubbe.bashApp {
        name = "oom-notify";
        runtimeInputs = with pkgs; [
          systemd
          jq
          libnotify
        ];
        text = ''
          journalctl --user --follow --lines=0 --output=json \
            ${lib.concatMapStringsSep " " (id: "MESSAGE_ID=${id}") (lib.attrNames oomKillMessages)} |
            jq --unbuffered --raw-output \
              --argjson killers ${lib.escapeShellArg (builtins.toJSON oomKillMessages)} \
              'select(.USER_UNIT | endswith(".slice") | not) | [.USER_UNIT, $killers[.MESSAGE_ID]] | @tsv' |
            while IFS=$'\t' read -r unit killer; do
              name=$unit
              if [[ $unit =~ ^app-[^-]+-(.+)-[0-9a-f]{8}\.scope$ || $unit =~ ^app-[^-]+-(.+)@[0-9a-f]+\.service$ ]]; then
                name=''${BASH_REMATCH[1]}
              fi
              notify-send --urgency=critical --app-name="Out of memory" \
                "Killed $name" "$killer stopped $unit to free memory"
            done
        '';
      };
    in
    {
      systemd.user.services.oom-notify = lib.mkIf config.features.desktop {
        Unit = {
          Description = "Desktop notification when an OOM killer stops a unit";
          After = [ config.wayland.systemd.target ];
          PartOf = [ config.wayland.systemd.target ];
        };
        Install.WantedBy = [ config.wayland.systemd.target ];
        Service = {
          ExecStart = lib.getExe oomNotify;
          Restart = "on-failure";
          RestartSec = "2s";
        };
      };

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
            - MGLRU min_ttl_ms=1000. When the working set of the last second can
              no longer stay resident, the kernel OOM-kills instead of thrashing
              the desktop into a multi-minute freeze.
            - earlyoom masked, systemd-oomd on. earlyoom's freeSwapThreshold
              cannot read zram (compressed "free swap" is not headroom) and it
              kills by RSS, so it reaches for mysqld or a Chrome renderer instead
              of whatever is thrashing. oomd is PSI- and cgroup-aware. Two OOM
              daemons with different policies is a race, so pick one.
            - oomd slice drop-ins. oomd only acts on cgroups that opt in, so
              without them it runs and never kills: the root, system and user
              slices kill on sustained memory pressure, and the root slice also
              kills the biggest swap user once zram is nearly full.

          Without zram, the OOM path fires under load and SIGTERMs Chrome/Electron
          renderers (oom_score_adj +300) across every chromium-family app
          ("Aw, Snap!", blank Slack). zram gives ~3x effective headroom so the
          threshold is rarely hit.
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

          ${pkgs.stubbe.setup.hostPackage {
            have = "systemctl list-unit-files systemd-oomd.service >/dev/null 2>&1";
            apt = [ "systemd-oomd" ];
            dnf = [ "systemd-oomd-defaults" ];
            pacman = [ "systemd" ];
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

          ${pkgs.stubbe.setup.text {
            name = "stubbe-memory-tmpfiles.conf";
            target = "/etc/tmpfiles.d/stubbe-memory.conf";
            text = pkgs.stubbe.managedBy "memory" + thrashingTmpfiles + "\n";
          }}
          sudo systemd-tmpfiles --create /etc/tmpfiles.d/stubbe-memory.conf

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
            sudo systemctl disable --now earlyoom.service
            sudo systemctl mask earlyoom.service
          fi
          sudo systemctl enable --now systemd-oomd.service

          ${pkgs.stubbe.setup.reloadUnits}
          sudo systemctl restart systemd-zram-setup@zram0.service
        '';
      };
    };
}
