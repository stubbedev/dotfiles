_: {
  flake.modules.nixos.power =
    {
      lib,
      pkgs,
      ...
    }:
    {
      services.power-profiles-daemon.enable = true;

      # Undocking or unplugging with the lid already closed is handled in
      # the hyprland monitor toggle script instead: logind only acts on the
      # lid switch edge (systemd#7690).
      services.logind.settings.Login = {
        HandleLidSwitch = "suspend";
        HandleLidSwitchExternalPower = "ignore";
        HandleLidSwitchDocked = "ignore";
      };

      # For the CLI (status, full) in user shells; the daemon runs from its
      # own store path below.
      environment.systemPackages = [ pkgs.adaptive-power-manager ];

      # battery-full's flag directory: group-writable so the user CLI can
      # drop a charge-to-full request without sudo.
      systemd.tmpfiles.rules = [ "d /run/battery-charge 0775 root users -" ];

      # Event-driven: UPower signals cover every AC edge, the daemon's tick
      # covers the prediction boundaries. No timer, no udev trigger.
      systemd.services.adaptive-power-manager = {
        description = "Adaptive battery charging and power profile policy";
        after = [
          "power-profiles-daemon.service"
          "upower.service"
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.adaptive-power-manager} run";
          StateDirectory = "adaptive-power-manager";
          Restart = "on-failure";
          RestartSec = "10s";
          # The sysfs threshold writes need root; everything else is contained.
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ "/sys/class/power_supply" ];
          ProtectHome = true;
          PrivateTmp = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
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
    let
      managedBy = pkgs.stubbe.managedBy "suspend-resume-recovery";

      sleepTargets = [
        "suspend.target"
        "hibernate.target"
        "hybrid-sleep.target"
        "suspend-then-hibernate.target"
      ];

      intelHybridModels = {
        alder-lake = [
          151
          154
        ];
        raptor-lake = [
          183
          186
          191
        ];
        meteor-lake = [
          170
          172
        ];
        lunar-lake = [ 189 ];
        panther-lake = [ 204 ];
      };
    in
    lib.mkIf config.features.desktop {
      home.packages = [
        (pkgs.stubbe.bashApp {
          name = "battery-full";
          text = "exec ${lib.getExe pkgs.adaptive-power-manager} full";
        })
      ];

      stubbe.setup = {
        powerSource = {
          privileged = true;
          title = "Installing adaptive-power-manager (profile + adaptive charging)";
          body = ''
            Two things that should follow the charger, and don't on their own,
            from one event-driven Go daemon (github.com/stubbedev/adaptive-power-manager):

            - power-profiles-daemon never switches by itself, so a "performance"
              profile picked while docked keeps draining after the undock. This
              drops to power-saver on unplug and back to performance on AC — only
              on an actual change, so a profile you pick by hand still sticks.
            - macOS-style Optimized Battery Charging. The 80% cap stays where it
              is; the daemon learns what time of day the charger actually comes
              out and raises the ceiling to 100% for the two hours before that,
              so the machine is full when you leave without sitting at 100% all
              week. Until a few unplugs are on record it just holds at 80%.

            Also installs `battery-full`, the "charge to full now" override — it
            lasts until you unplug, which is also when the cap comes back.

            Replaces the bash power-source policy: its units, udev rule and
            script are retired here, and the recorded unplug history carries
            over automatically.
          '';
          script =
            let
              toUnit = pkgs.stubbe.gen.unitText;
              binPath = "/usr/local/bin/adaptive-power-manager";
            in
            ''
              PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

              # Installed by value, not symlinked: the boot service must
              # survive a nix-collect-garbage.
              install -m 0755 "${pkgs.adaptive-power-manager}/bin/adaptive-power-manager" "${binPath}"

              ${pkgs.stubbe.setup.text {
                name = "adaptive-power-manager-tmpfiles.conf";
                target = "/etc/tmpfiles.d/adaptive-power-manager.conf";
                text = "d /run/battery-charge 0775 root users -\n";
              }}

              ${pkgs.stubbe.setup.text {
                name = "adaptive-power-manager.service";
                target = "/etc/systemd/system/adaptive-power-manager.service";
                text = toUnit {
                  Unit = {
                    Description = "Adaptive battery charging and power profile policy";
                    After = "power-profiles-daemon.service upower.service";
                  };
                  Service = {
                    Type = "simple";
                    ExecStart = "${binPath} run";
                    StateDirectory = "adaptive-power-manager";
                    Restart = "on-failure";
                    RestartSec = "10s";
                    NoNewPrivileges = true;
                    ProtectSystem = "strict";
                    ReadWritePaths = "/sys/class/power_supply";
                    ProtectHome = true;
                    PrivateTmp = true;
                    ProtectKernelTunables = true;
                    ProtectControlGroups = true;
                    RestrictSUIDSGID = true;
                    LockPersonality = true;
                  };
                  Install.WantedBy = "multi-user.target";
                };
              }}

              # Retire the bash policy this replaces.
              sudo systemctl disable --now power-source.timer power-source-full.path power-source.service >/dev/null 2>&1 || true
              sudo rm -f \
                /etc/systemd/system/power-source.service \
                /etc/systemd/system/power-source.timer \
                /etc/systemd/system/power-source-full.path \
                /etc/udev/rules.d/85-power-source.rules \
                /usr/local/sbin/power-source.sh

              sudo systemd-tmpfiles --create /etc/tmpfiles.d/adaptive-power-manager.conf >/dev/null 2>&1 || true
              ${pkgs.stubbe.setup.reloadUnits}
              sudo systemctl enable --now adaptive-power-manager.service >/dev/null 2>&1 || true
            '';
        };

        # Deliberately absent, each having been tried:
        #   - a static batteryChargeThreshold udev rule: the daemon restores
        #     the cap on the unplug edge itself, so the rule only fought it.
        #   - thermald refuses to start where thinkpad_acpi/dytc_lapmode exists.
        #   - wifi powersave toggling: NetworkManager already sets powersave=3,
        #     and the AC half turns it back off for a net loss.
        #   - USB autosuspend is disabled on purpose (modules/hardware.nix).
        batteryPower = {
          privileged = true;
          title = "Installing battery power tuning";
          preCheck = pkgs.stubbe.setup.requirePath "/sys/class/power_supply/BAT0";
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

            cpu_model=$(awk -F: '/^model[[:space:]]*:/ { gsub(/ /, "", $2); print $2; exit }' /proc/cpuinfo)
            case "$cpu_model" in
            ${
              lib.concatMapStringsSep " | " toString (
                lib.sort (a: b: a < b) (lib.concatLists (lib.attrValues intelHybridModels))
              )
            })
              ${pkgs.stubbe.setup.hostPackage {
                detect = "intel_lpmd";
                apt = [ "intel-lpmd" ];
                dnf = [ "intel-lpmd" ];
                pacman = [ "intel-lpmd" ];
              }}
              sudo systemctl enable --now intel_lpmd.service >/dev/null 2>&1 || true
              ;;
            esac

            if systemctl list-unit-files plocate-updatedb.service >/dev/null 2>&1; then
              ${pkgs.stubbe.setup.text {
                name = "plocate-ac-only.conf";
                target = "/etc/systemd/system/plocate-updatedb.service.d/ac-only.conf";
                text =
                  pkgs.stubbe.managedBy "battery-power" + pkgs.stubbe.gen.iniText { Unit.ConditionACPower = true; };
              }}
              ${pkgs.stubbe.setup.reloadUnits}
            fi
          '';
        };

        logindLid = {
          privileged = true;
          title = "Installing systemd-logind lid switch handler";
          body = ''
            macOS-style lid behaviour: closing the lid suspends (s2idle) on
            battery, but stays awake on AC — clamshell with an external
            display (logind's "docked" state counts connected non-eDP DRM
            connectors) or headless, so SSH sessions and long builds survive.
            Opening the lid wakes.

            Undocking or unplugging with the lid already closed is handled
            separately by the hyprland monitor toggle script — logind only
            acts on the lid switch edge, not on later display or power
            changes (systemd#7690).
          '';
          script = ''
            ${pkgs.stubbe.setup.text {
              name = "10-lid.conf";
              target = "/etc/systemd/logind.conf.d/10-lid.conf";
              text =
                pkgs.stubbe.managedBy "logind-lid"
                + pkgs.stubbe.gen.iniText {
                  Login = {
                    HandleLidSwitch = "suspend";
                    HandleLidSwitchExternalPower = "ignore";
                    HandleLidSwitchDocked = "ignore";
                  };
                };
            }}

            if command -v systemctl >/dev/null 2>&1; then
              sudo systemctl kill -s HUP systemd-logind.service >/dev/null 2>&1 || true
            fi
          '';
        };

        suspendResumeRecovery = {
          privileged = true;
          title = "Installing suspend/resume network recovery";
          body = ''
            A suspend that stalls past logind's 3min watchdog gets it SIGABRT'd on
            resume, and the replacement never delivers the PrepareForSleep(false)
            NetworkManager is waiting on, so NetworkManager stays ASLEEP and
            manages nothing — no wifi, no wired, until a reboot. Raises the
            watchdog, and wakes NetworkManager anyway when it still dies.
          '';
          stateInputs = [ "/etc/systemd/system/nm-wake-after-resume.service" ];
          script = ''
            ${pkgs.stubbe.setup.text {
              name = "watchdog.conf";
              target = "/etc/systemd/system/systemd-logind.service.d/watchdog.conf";
              text = managedBy + pkgs.stubbe.gen.iniText { Service.WatchdogSec = "15min"; };
            }}

            ${pkgs.stubbe.setup.text {
              name = "nm-wake-after-resume.service";
              target = "/etc/systemd/system/nm-wake-after-resume.service";
              text =
                managedBy
                + pkgs.stubbe.gen.unitText {
                  Unit = {
                    Description = "Wake NetworkManager after resume";
                    After = sleepTargets ++ [ "NetworkManager.service" ];
                  };
                  Service = {
                    Type = "oneshot";
                    # "-": exits 1 with "Already awake" on every normal resume.
                    ExecStart = "-/usr/bin/busctl call org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Sleep b false";
                  };
                  Install.WantedBy = sleepTargets;
                };
            }}

            ${pkgs.stubbe.setup.reloadUnits}
            sudo systemctl enable nm-wake-after-resume.service >/dev/null
          '';
        };
      };
    };
}
