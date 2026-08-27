# Power: what the machine does when the charger comes and goes, when the lid
# closes, and how long the battery lasts.
#
# The reactive core is one shell script (src/power/power-source.sh) deployed
# two ways — a NixOS service + udev rule, or the equivalent files written into
# /etc by a privileged activation. Both halves are here, so the unit shape and
# the script cannot drift apart.
_: {
  flake.modules.nixos.power =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      powerSourceScript = pkgs.stubbe.text "src/power/power-source.sh";
    in
    {
      # Provides the system D-Bus service at /net/hadess/PowerProfiles, which
      # wayle's power-profiles module reads (and sets on left-click ":cycle").
      # Without it the module reads "unknown".
      #
      # PPD alone handles CPU scaling (platform_profile + EPP) since the Lunar
      # Lake 400MHz firmware bug was fixed in BIOS 1.45 — the old
      # power.profile.fix.sh layer and intel_pstate=passive are gone.
      services.power-profiles-daemon.enable = true;

      # macOS-style lid behaviour: closing the lid suspends on battery and on
      # AC, but the machine stays awake in clamshell mode when an external
      # display is connected ("docked" counts connected non-eDP DRM
      # connectors). Undocking with the lid already closed is handled by
      # src/hyprland/scripts/monitor.toggle.sh — logind only acts on the lid
      # switch edge (systemd#7690).
      services.logind.settings.Login = {
        HandleLidSwitch = "suspend";
        HandleLidSwitchExternalPower = "suspend";
        HandleLidSwitchDocked = "ignore";
      };

      # 0775 root:users so `battery-full` can drop the override flag without
      # sudo — the .path unit below turns that into an immediate run.
      systemd.tmpfiles.rules = [ "d /run/battery-charge 0775 root users -" ];

      systemd.services.power-source = {
        description = "Apply power-source policy (profile + charge threshold)";
        # Ordering only, no `wants`: the charging half still has work to do on
        # a host where power-profiles-daemon is not running.
        after = [ "power-profiles-daemon.service" ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "power-source";
        };
        # `script` rather than writeShellApplication: that wrapper forces
        # `set -e`, under which the "already at the wanted thresholds" guard
        # (`[ a = b ] && [ c = d ] && exit 0`) would abort the script whenever
        # it is false — which is the common path.
        path = with pkgs; [
          coreutils
          gawk
          power-profiles-daemon
        ];
        script = powerSourceScript;
      };

      # Immediate reaction to plug/unplug — the timer alone would leave a
      # performance profile draining the battery for up to five minutes. Both
      # Mains and USB: with a USB-C-only charger the AC device may never fire
      # an event. --no-block keeps the udev worker free while the unit runs,
      # and this also fires on the boot coldplug, so no separate init unit.
      services.udev.extraRules =
        let
          run = "${lib.getExe' config.systemd.package "systemctl"} --no-block start power-source.service";
        in
        ''
          SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${run}"
          SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="${run}"
        '';

      # Catches the approach of the usual unplug time. A run costs nothing: on
      # battery the script exits right after recording, and the profile half
      # only acts on a change.
      systemd.timers.power-source = {
        description = "Re-evaluate power-source policy";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
          AccuracySec = "1min";
        };
      };

      # Makes `battery-full` take effect at once instead of at the next tick.
      systemd.paths.power-source-full = {
        description = "Watch for a manual charge-to-full request";
        wantedBy = [ "paths.target" ];
        pathConfig = {
          PathExists = "/run/battery-charge/full-now";
          Unit = "power-source.service";
        };
      };
    };

  flake.modules.homeManager.power =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.desktop {
      # "Charge to full now" override for power-source: drops a flag file the
      # power-source-full.path unit is watching, so no sudo is needed.
      home.packages = [
        (pkgs.stubbe.scriptBin {
          name = "battery-full";
          source = "src/power/battery-full.sh";
        })
      ];

      stubbe.setup = {
        # The non-NixOS half of the NixOS block above: same script, same unit
        # shape, written into /etc with FHS paths.
        powerSource = {
          privileged = true;
          title = "Installing power-source policy (profile + adaptive charging)";
          preCheck = pkgs.stubbe.requirePath "/sys/class/power_supply/BAT0/charge_control_end_threshold";
          body = ''
            Two things that should follow the charger, and don't on their own:

            - power-profiles-daemon never switches by itself, so a "performance"
              profile picked while docked keeps draining after the undock. This
              drops to power-saver on unplug and back to performance on AC — only
              on an actual change, so a profile you pick by hand still sticks.
            - macOS-style Optimized Battery Charging. The 80% cap stays where it
              is; this learns what time of day the charger actually comes out and
              raises the ceiling to 100% for the two hours before that, so the
              machine is full when you leave without sitting at 100% all week.
              Until a few unplugs are on record it just holds at 80%.

            Also installs `battery-full`, the "charge to full now" override — it
            lasts until you unplug.
          '';
          script =
            let
              toUnit = lib.generators.toINI { listsAsDuplicateKeys = true; };
              scriptPath = "/usr/local/sbin/power-source.sh";
            in
            ''
              PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

              ${pkgs.stubbe.installFile {
                source = pkgs.stubbe.file "src/power/power-source.sh";
                target = scriptPath;
                mode = "0755";
              }}

              ${pkgs.stubbe.installText {
                name = "power-source-tmpfiles.conf";
                target = "/etc/tmpfiles.d/power-source.conf";
                text = "d /run/battery-charge 0775 root users -\n";
              }}

              ${pkgs.stubbe.installText {
                name = "85-power-source.rules";
                target = "/etc/udev/rules.d/85-power-source.rules";
                text = ''
                  SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemctl --no-block start power-source.service"
                  SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemctl --no-block start power-source.service"
                '';
              }}

              ${pkgs.stubbe.installText {
                name = "power-source.service";
                target = "/etc/systemd/system/power-source.service";
                text = toUnit {
                  Unit = {
                    Description = "Apply power-source policy (profile + charge threshold)";
                    After = "power-profiles-daemon.service";
                  };
                  Service = {
                    Type = "oneshot";
                    ExecStart = scriptPath;
                    StateDirectory = "power-source";
                  };
                };
              }}

              ${pkgs.stubbe.installText {
                name = "power-source.timer";
                target = "/etc/systemd/system/power-source.timer";
                text = toUnit {
                  Unit.Description = "Re-evaluate power-source policy";
                  Timer = {
                    OnBootSec = "2min";
                    OnUnitActiveSec = "5min";
                    AccuracySec = "1min";
                  };
                  Install.WantedBy = "timers.target";
                };
              }}

              ${pkgs.stubbe.installText {
                name = "power-source-full.path";
                target = "/etc/systemd/system/power-source-full.path";
                text = toUnit {
                  Unit.Description = "Watch for a manual charge-to-full request";
                  Path = {
                    PathExists = "/run/battery-charge/full-now";
                    Unit = "power-source.service";
                  };
                  Install.WantedBy = "paths.target";
                };
              }}

              sudo systemd-tmpfiles --create /etc/tmpfiles.d/power-source.conf >/dev/null 2>&1 || true
              sudo systemctl daemon-reload
              sudo systemctl enable --now power-source.timer power-source-full.path >/dev/null 2>&1 || true

              # Reload rules so the next plug event picks them up. No trigger:
              # see the usbPower setup in modules/hardware.nix for why
              # re-running power_supply add events on this machine is a bad idea.
              if command -v udevadm >/dev/null 2>&1; then
                sudo udevadm control --reload-rules >/dev/null 2>&1 || true
              fi
            '';
        };

        # 80% charge cap, the single biggest lever on battery lifespan.
        batteryChargeThreshold = {
          privileged = true;
          title = "Installing battery charge threshold (80%)";
          body = ''
            This machine spends most of its life on a dock; holding lithium at
            100% is what ages it fastest. This installs a udev rule that caps
            charging at 80% (resume below 75%) via the ThinkPad EC, and applies
            the thresholds immediately. Costs ~1h of unplugged runtime; buys
            battery capacity measured in years. Charge to full for a trip with
            `battery-full` — the rule drops back to 80% the moment you unplug,
            so there is nothing to remember to undo. Worth doing every few
            months anyway: the EC only recalibrates its full-charge estimate on
            a complete charge, so a battery that never finishes reports a health
            figure that drifts low.
          '';
          script = ''
            ${pkgs.stubbe.installFile {
              source = pkgs.stubbe.file "src/power/85-battery-charge-threshold.rules";
              target = "/etc/udev/rules.d/85-battery-charge-threshold.rules";
            }}

            if command -v udevadm >/dev/null 2>&1; then
              sudo udevadm control --reload-rules >/dev/null 2>&1 || true
            fi

            # Apply now — the rule only fires on the next battery "add" (boot).
            # start first: 75 is below any current end, and end=80 is above 75,
            # so the EC accepts both writes in this order from any prior state.
            bat=/sys/class/power_supply/BAT0
            if [ -f "$bat/charge_control_end_threshold" ]; then
              echo 75 | sudo tee "$bat/charge_control_start_threshold" >/dev/null
              echo 80 | sudo tee "$bat/charge_control_end_threshold" >/dev/null
            fi
          '';
        };

        # Host-package-level battery tuning, ported from omarchy's power
        # scripts. Deliberately NOT ported, because none of it helps here:
        #   - thermald: refuses to start on ThinkPads exposing
        #     thinkpad_acpi/dytc_lapmode ("Thermald can't run on this
        #     platform") — DYTC/platform_profile already owns thermal policy.
        #   - wifi powersave toggling: NetworkManager already ships
        #     wifi.powersave=3 (always on), which is the state omarchy's udev
        #     rule aims for; its AC half turns it back off, a net loss.
        #   - disabling USB autosuspend: costs battery, and is installed on
        #     purpose (audio pops on the dock) — see modules/hardware.nix.
        batteryPower = {
          privileged = true;
          title = "Installing battery power tuning";
          preCheck = pkgs.stubbe.requirePath "/sys/class/power_supply/BAT0";
          body = ''
            Two unplugged-runtime fixes for this laptop:

            - intel-lpmd, Intel's low power mode daemon. On hybrid CPUs (Lunar
              Lake here) it parks the workload on the low-power E-core island
              while the machine is near-idle, which is where a laptop spends most
              of its day.
            - plocate's weekly reindex restricted to AC power, so it can't wake
              the disk and burn a chunk of the battery mid-flight.
          '';
          script = ''
            PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

            # intel-lpmd only has a CPU topology to work with on Intel hybrid
            # parts. Model list from omarchy: Alder Lake (151/154), Raptor Lake
            # (183/186/191), Meteor Lake (170/172), Lunar Lake (189), Panther
            # Lake (204). Anything else, skip — the daemon would just exit.
            cpu_model=$(awk -F: '/^model[[:space:]]*:/ { gsub(/ /, "", $2); print $2; exit }' /proc/cpuinfo)
            case "$cpu_model" in
            151 | 154 | 170 | 172 | 183 | 186 | 189 | 191 | 204)
              ${pkgs.stubbe.installHostPackage {
                detect = "intel_lpmd";
                apt = [ "intel-lpmd" ];
                dnf = [ "intel-lpmd" ];
                pacman = [ "intel-lpmd" ];
              }}
              sudo systemctl enable --now intel_lpmd.service >/dev/null 2>&1 || true
              ;;
            esac

            # plocate's reindex walks the whole filesystem; on battery that is
            # minutes of disk and CPU for a search index nobody is querying
            # while unplugged. systemd re-runs it once AC is back.
            if systemctl list-unit-files plocate-updatedb.service >/dev/null 2>&1; then
              ${pkgs.stubbe.installText {
                name = "plocate-ac-only.conf";
                target = "/etc/systemd/system/plocate-updatedb.service.d/ac-only.conf";
                text = ''
                  # managed-by: stubbe battery-power
                  [Unit]
                  ConditionACPower=true
                '';
              }}
              sudo systemctl daemon-reload
            fi
          '';
        };

        # macOS-style lid behaviour; the NixOS half is services.logind above.
        logindLid = {
          privileged = true;
          title = "Installing systemd-logind lid switch handler";
          body = ''
            macOS-style lid behaviour: closing the lid suspends (s2idle) on
            battery and on AC, but the machine stays awake in clamshell mode
            when an external display is connected (logind's "docked" state
            counts connected non-eDP DRM connectors). Opening the lid wakes.

            Undocking with the lid already closed is handled separately by
            src/hyprland/scripts/monitor.toggle.sh — logind only acts on the
            lid switch edge, not on later display changes (systemd#7690).
          '';
          script = ''
            ${pkgs.stubbe.installText {
              name = "10-lid.conf";
              target = "/etc/systemd/logind.conf.d/10-lid.conf";
              text = ''
                # managed-by: stubbe logind-lid
                [Login]
                HandleLidSwitch=suspend
                HandleLidSwitchExternalPower=suspend
                HandleLidSwitchDocked=ignore
              '';
            }}

            if command -v systemctl >/dev/null 2>&1; then
              sudo systemctl kill -s HUP systemd-logind.service >/dev/null 2>&1 || true
            fi
          '';
        };
      };
    };
}
