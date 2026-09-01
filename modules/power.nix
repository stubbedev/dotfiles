_: {
  # No shebang and no strict mode: under `set -e` the "already at the wanted
  # thresholds" guard aborts the script whenever it is false, the common path.
  stubbe.lib.powerSourceScript = ''
    set -u

    supplies=''${POWER_SOURCE_SUPPLY_DIR:-/sys/class/power_supply}
    bat=''${POWER_SOURCE_BAT:-$supplies/BAT0}
    state=''${POWER_SOURCE_STATE_DIR:-/var/lib/power-source}
    runtime=''${POWER_SOURCE_RUNTIME_DIR:-/run/battery-charge}
    hist=$state/unplugs
    last_ac_file=$state/last-ac
    full_now=$runtime/full-now

    base_start=75
    base_end=80
    full_start=95
    full_end=100
    topup_window_min=120
    min_samples=3
    hist_max=60

    mkdir -p "$state"

    on_ac=0
    for ps in "$supplies"/*; do
      [ -r "$ps/type" ] && [ -r "$ps/online" ] || continue
      case "$(cat "$ps/type")" in
      Mains | USB) ;;
      *) continue ;;
      esac
      if [ "$(cat "$ps/online")" = "1" ]; then
        on_ac=1
        break
      fi
    done

    read -r dow hour minute <<<"''${POWER_SOURCE_NOW:-$(date '+%u %H %M')}"
    now_min=$((10#$hour * 60 + 10#$minute))

    prev_ac=$(cat "$last_ac_file" 2>/dev/null || printf 'unknown')
    printf '%s' "$on_ac" >"$last_ac_file"

    if [ "$prev_ac" != "$on_ac" ] && command -v powerprofilesctl >/dev/null 2>&1; then
      profiles=$(powerprofilesctl list 2>/dev/null)
      if [ "$on_ac" = 1 ]; then
        case "$profiles" in
        *performance:*) powerprofilesctl set performance ;;
        *) powerprofilesctl set balanced ;;
        esac
      else
        case "$profiles" in
        *power-saver:*) powerprofilesctl set power-saver ;;
        *) powerprofilesctl set balanced ;;
        esac
      fi
    fi

    if [ "$prev_ac" = 1 ] && [ "$on_ac" = 0 ]; then
      printf '%s %s\n' "$dow" "$now_min" >>"$hist"
      if [ "$(wc -l <"$hist")" -gt "$hist_max" ]; then
        tail -n "$hist_max" "$hist" >"$hist.tmp" && mv "$hist.tmp" "$hist"
      fi
      rm -f "$full_now"
    fi

    [ "$on_ac" = 1 ] || exit 0
    [ -w "$bat/charge_control_end_threshold" ] || exit 0

    predict_unplug() {
      awk -v dow="$dow" -v now="$now_min" -v need="$min_samples" '
        $2 > now {
          all[na++] = $2
          if ($1 == dow) same[ns++] = $2
        }
        END {
          if (ns >= need)      { n = ns; for (i = 0; i < n; i++) v[i] = same[i] }
          else if (na >= need) { n = na; for (i = 0; i < n; i++) v[i] = all[i] }
          else                 { exit 1 }
          for (i = 1; i < n; i++) {
            x = v[i]
            for (j = i - 1; j >= 0 && v[j] > x; j--) v[j + 1] = v[j]
            v[j + 1] = x
          }
          print v[int((n - 1) / 4)]
        }
      ' "$hist" 2>/dev/null
    }

    want_start=$base_start
    want_end=$base_end
    if [ -e "$full_now" ]; then
      want_start=$full_start
      want_end=$full_end
    elif predicted=$(predict_unplug) && [ $((predicted - now_min)) -le "$topup_window_min" ]; then
      want_start=$full_start
      want_end=$full_end
    fi

    cur_end=$(cat "$bat/charge_control_end_threshold")
    cur_start=$(cat "$bat/charge_control_start_threshold")
    [ "$cur_end" = "$want_end" ] && [ "$cur_start" = "$want_start" ] && exit 0

    if [ "$want_end" -gt "$cur_end" ]; then
      printf '%s' "$want_end" >"$bat/charge_control_end_threshold"
      printf '%s' "$want_start" >"$bat/charge_control_start_threshold"
    else
      printf '%s' "$want_start" >"$bat/charge_control_start_threshold"
      printf '%s' "$want_end" >"$bat/charge_control_end_threshold"
    fi
  '';

  flake.modules.nixos.power =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      services.power-profiles-daemon.enable = true;

      # Undocking with the lid already closed is handled in
      # src/hyprland/scripts/monitor.toggle.sh instead: logind only acts on the
      # lid switch edge (systemd#7690).
      services.logind.settings.Login = {
        HandleLidSwitch = "suspend";
        HandleLidSwitchExternalPower = "suspend";
        HandleLidSwitchDocked = "ignore";
      };

      systemd.tmpfiles.rules = [ "d /run/battery-charge 0775 root users -" ];

      systemd.services.power-source = {
        description = "Apply power-source policy (profile + charge threshold)";
        after = [ "power-profiles-daemon.service" ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "power-source";
        };
        path = with pkgs; [
          coreutils
          gawk
          power-profiles-daemon
        ];
        script = pkgs.stubbe.powerSourceScript;
      };

      # Both Mains and USB: a USB-C-only charger may never fire an AC event.
      # --no-block keeps the udev worker free; the boot coldplug fires it too,
      # so no separate init unit is needed.
      services.udev.extraRules =
        let
          run = "${lib.getExe' config.systemd.package "systemctl"} --no-block start power-source.service";
        in
        ''
          SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${run}"
          SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="${run}"
        '';

      systemd.timers.power-source = {
        description = "Re-evaluate power-source policy";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
          AccuracySec = "1min";
        };
      };

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
          text = ''
            dir=/run/battery-charge

            if [ ! -d "$dir" ]; then
              echo "battery-full: $dir is missing — is power-source.timer enabled?" >&2
              exit 1
            fi

            touch "$dir/full-now"
            echo "Charging to 100%. The 80% cap comes back when you unplug."
          '';
        })
      ];

      stubbe.setup = {
        powerSource = {
          privileged = true;
          title = "Installing power-source policy (profile + adaptive charging)";
          preCheck = pkgs.stubbe.setup.requirePath "/sys/class/power_supply/BAT0/charge_control_end_threshold";
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
              toUnit = pkgs.stubbe.gen.unitText;
              scriptPath = "/usr/local/sbin/power-source.sh";
            in
            ''
              PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

              ${pkgs.stubbe.setup.text {
                name = "power-source.sh";
                target = scriptPath;
                mode = "0755";
                # Host bash: this copy lives in /usr/local and must survive a
                # nix-collect-garbage.
                text = "#!/usr/bin/env bash\n" + pkgs.stubbe.powerSourceScript;
              }}

              ${pkgs.stubbe.setup.text {
                name = "power-source-tmpfiles.conf";
                target = "/etc/tmpfiles.d/power-source.conf";
                text = "d /run/battery-charge 0775 root users -\n";
              }}

              ${pkgs.stubbe.setup.text {
                name = "85-power-source.rules";
                target = "/etc/udev/rules.d/85-power-source.rules";
                text = ''
                  SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemctl --no-block start power-source.service"
                  SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemctl --no-block start power-source.service"
                '';
              }}

              ${pkgs.stubbe.setup.text {
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

              ${pkgs.stubbe.setup.text {
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

              ${pkgs.stubbe.setup.text {
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
              ${pkgs.stubbe.setup.reloadUnits}
              sudo systemctl enable --now power-source.timer power-source-full.path >/dev/null 2>&1 || true

              ${pkgs.stubbe.setup.reloadUdev}
            '';
        };

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
            ${pkgs.stubbe.setup.text {
              name = "85-battery-charge-threshold.rules";
              target = "/etc/udev/rules.d/85-battery-charge-threshold.rules";
              text = ''
                ACTION=="add", SUBSYSTEM=="power_supply", KERNEL=="BAT0", ATTR{charge_control_start_threshold}="75", ATTR{charge_control_end_threshold}="80"

                ACTION=="change", SUBSYSTEM=="power_supply", KERNEL=="BAT0", ATTR{status}=="Discharging", ATTR{charge_control_end_threshold}!="80", ATTR{charge_control_start_threshold}="75", ATTR{charge_control_end_threshold}="80"
              '';
            }}

            ${pkgs.stubbe.setup.reloadUdev}

            bat=/sys/class/power_supply/BAT0
            if [ -f "$bat/charge_control_end_threshold" ]; then
              echo 75 | sudo tee "$bat/charge_control_start_threshold" >/dev/null
              echo 80 | sudo tee "$bat/charge_control_end_threshold" >/dev/null
            fi
          '';
        };

        # Deliberately absent, each having been tried:
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
            battery and on AC, but the machine stays awake in clamshell mode
            when an external display is connected (logind's "docked" state
            counts connected non-eDP DRM connectors). Opening the lid wakes.

            Undocking with the lid already closed is handled separately by
            src/hyprland/scripts/monitor.toggle.sh — logind only acts on the
            lid switch edge, not on later display changes (systemd#7690).
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
                    HandleLidSwitchExternalPower = "suspend";
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
