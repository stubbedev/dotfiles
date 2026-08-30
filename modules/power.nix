# Power: what the machine does when the charger comes and goes, when the lid
# closes, and how long the battery lasts.
#
# The reactive core is one shell script (`stubbe.lib.powerSourceScript` below)
# deployed two ways — a NixOS service + udev rule, or the equivalent files
# written into /etc by a privileged activation. Both halves are here, so the
# unit shape and the script cannot drift apart. The script lives in
# `stubbe.lib` so modules/dev/power-source.nix tests the exact deployed bytes.
_: {
  # No shebang and no strict mode: the NixOS half runs it via systemd `script`,
  # and under `set -e` the "already at the wanted thresholds" guard
  # (`[ a = b ] && [ c = d ] && exit 0`) would abort the script whenever it is
  # false — which is the common path.
  stubbe.lib.powerSourceScript = ''
    # Everything this machine does in reaction to the power source: pick the
    # power-profiles-daemon profile, and decide how far to charge the battery.
    #
    # One script because both halves need the same "are we on AC" answer, which is
    # not the one-liner it looks like (see the probe below), and because both want
    # to know when that answer *changed*.
    #
    # Charging follows what macOS calls Optimized Battery Charging: hold at 80%
    # while the machine sits on the dock, and only finish to 100% shortly before
    # it is actually going to be unplugged. ChromeOS ships the same idea in powerd
    # behind an ML model that scores each of the next eight hours; nothing
    # equivalent is packaged for generic Linux, so this is the statistical
    # stand-in — log when the charger really comes out, and top up when now is
    # inside the window before the usual time for this weekday.
    #
    # The 80% floor itself lives in udev (85-battery-charge-threshold.rules), so
    # the cap is right at boot and on unplug even if this never runs. Everything
    # here only ever moves the ceiling up, and only temporarily.
    #
    # Runs as root (the EC thresholds need it) from three triggers:
    #   - the power_supply udev rule, for an immediate reaction to plug/unplug
    #   - a 5-minute timer, to notice that the usual unplug time is approaching
    #   - a .path unit watching the `battery-full` override flag
    # Wired up by modules/power.nix (NixOS) and
    # modules/power.nix (everything else).
    set -u

    # ponytail: these five env vars are test seams, not configuration — they let
    # modules/dev/power-source.nix point the script at a fake sysfs tree and a
    # fixed clock. Nothing sets them in production.
    supplies=''${POWER_SOURCE_SUPPLY_DIR:-/sys/class/power_supply}
    bat=''${POWER_SOURCE_BAT:-$supplies/BAT0}
    state=''${POWER_SOURCE_STATE_DIR:-/var/lib/power-source}
    runtime=''${POWER_SOURCE_RUNTIME_DIR:-/run/battery-charge}
    hist=$state/unplugs
    last_ac_file=$state/last-ac
    full_now=$runtime/full-now

    # Base cap, matched to 85-battery-charge-threshold.rules.
    base_start=75
    base_end=80
    # Top-up pair. start has to rise with end: the EC only resumes charging below
    # start, so leaving it at 75 would mean a pack sitting at 80% never actually
    # climbs to the raised ceiling.
    full_start=95
    full_end=100
    # ChromeOS holds at 80% while it predicts more than two hours of AC left. Same
    # number here: 80 → 100 takes well under an hour once the charge current
    # tapers, so two hours leaves room for the prediction to be wrong.
    topup_window_min=120
    # Below this many recorded unplugs the routine isn't a routine yet, and the cap
    # stays at 80. macOS instead charges to 100% when it can't predict you; holding
    # is the safer default and matches what this laptop did before.
    min_samples=3
    # Two months of routine. Not a size limit — a relevance one: a job that moved
    # to a different schedule should stop being predicted from the old one.
    hist_max=60

    mkdir -p "$state"

    # Any Mains or USB supply reporting online=1 counts as AC. USB-C charging shows
    # up on a ucsi-source-psy-* device rather than on AC, and the ports that aren't
    # feeding power read online=0 — so this has to be an OR over every supply, not
    # a look at AC alone.
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

    # "unknown" on the first run, so a fresh boot counts as a change and lands on
    # the right profile without a separate init unit.
    prev_ac=$(cat "$last_ac_file" 2>/dev/null || printf 'unknown')
    printf '%s' "$on_ac" >"$last_ac_file"

    # ---------------------------------------------------------------- profile ---
    # PPD has no auto-switching of its own: whatever profile is active when the
    # charger comes out stays active, so a "performance" picked while docked keeps
    # burning battery all session. Only on an actual change, though — the timer
    # runs every five minutes, and a profile chosen by hand from the bar has to
    # survive until the next plug or unplug.
    if [ "$prev_ac" != "$on_ac" ] && command -v powerprofilesctl >/dev/null 2>&1; then
      # Not every platform exposes every profile, so pick from what's listed.
      profiles=$(powerprofilesctl list 2>/dev/null)
      if [ "$on_ac" = 1 ]; then
        case "$profiles" in
        *performance:*) powerprofilesctl set performance ;;
        *) powerprofilesctl set balanced ;;
        esac
      else
        # power-saver, where omarchy drops to balanced — the unplugged case is the
        # whole point. Click back up in the bar for a build that needs the cores.
        case "$profiles" in
        *power-saver:*) powerprofilesctl set power-saver ;;
        *) powerprofilesctl set balanced ;;
        esac
      fi
    fi

    # --------------------------------------------------------------- charging ---
    if [ "$prev_ac" = 1 ] && [ "$on_ac" = 0 ]; then
      # Charger just came out. Also drop any manual "charge to full": it applies to
      # the session that asked for it, not to the next one.
      printf '%s %s\n' "$dow" "$now_min" >>"$hist"
      if [ "$(wc -l <"$hist")" -gt "$hist_max" ]; then
        tail -n "$hist_max" "$hist" >"$hist.tmp" && mv "$hist.tmp" "$hist"
      fi
      rm -f "$full_now"
    fi

    # Nothing to decide on battery — the udev rule already put the cap back.
    [ "$on_ac" = 1 ] || exit 0
    [ -w "$bat/charge_control_end_threshold" ] || exit 0

    # Usual unplug time for this weekday, in minutes past midnight, or exit 1 when
    # there isn't enough history to say. Only unplugs still ahead of us today
    # count: at 22:00 an 08:30 routine says nothing about tonight, and holding at
    # 80 through the night is exactly right.
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
          # Hand-rolled insertion sort: asort() is a gawk extension, and n is
          # capped at the history size anyway.
          for (i = 1; i < n; i++) {
            x = v[i]
            for (j = i - 1; j >= 0 && v[j] > x; j--) v[j + 1] = v[j]
            v[j + 1] = x
          }
          # Lower quartile rather than the median. Being an hour early costs a
          # little time at high charge; being an hour late means walking out at
          # 80%, which is the failure the whole feature exists to avoid.
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

    # The EC rejects any write that would leave start above end, so the pair has to
    # be written in the order that keeps start <= end true at every step: raise the
    # ceiling first when going up, lower the floor first when coming down.
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
        script = pkgs.stubbe.powerSourceScript;
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
    let
      # Intel hybrid parts, by family — intel-lpmd only has a P/E-core topology
      # to work with on these, and exits immediately anywhere else. The numbers
      # are CPUID model IDs as /proc/cpuinfo reports them (list from omarchy).
      # Keyed by family so a new generation is one named line rather than a
      # digit appended to a bare run of numbers and a comment to keep in sync.
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
      # "Charge to Full Now" — the button macOS puts next to Optimized Battery
      # Charging. Lifts the 80% cap for the rest of this charging session;
      # unplugging clears it and the cap comes straight back. Just drops a flag
      # file: power-source-full.path is watching for it and starts
      # power-source.service the moment it appears, so no sudo and no waiting
      # for the next timer tick.
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

              ${pkgs.stubbe.installText {
                name = "power-source.sh";
                target = scriptPath;
                mode = "0755";
                # env-resolved host bash: this copy lives in /usr/local and
                # must survive a nix-collect-garbage.
                text = "#!/usr/bin/env bash\n" + pkgs.stubbe.powerSourceScript;
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
            ${pkgs.stubbe.installText {
              name = "85-battery-charge-threshold.rules";
              target = "/etc/udev/rules.d/85-battery-charge-threshold.rules";
              text = ''
                # Cap charging at 80% for battery longevity; resume charging below 75%
                # so a docked machine doesn't micro-cycle between 79 and 80.
                # start is assigned before end: from any state 75 < current end always
                # holds, and end=80 > 75 — either write alone would be rejected by the
                # EC if it crossed the other threshold.
                ACTION=="add", SUBSYSTEM=="power_supply", KERNEL=="BAT0", ATTR{charge_control_start_threshold}="75", ATTR{charge_control_end_threshold}="80"

                # Restore the cap on unplug, so raising it for a trip
                #   echo 100 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold
                # reverts itself the moment the charger comes out, instead of leaving the
                # machine parked at 100% on the dock for weeks — which is the wear this
                # whole file exists to avoid. Relying on the boot rule above isn't enough:
                # this laptop suspends far more often than it reboots.
                #
                # BAT0 emits a change event on the AC transition. The end!="80" match keeps
                # this to a single EC write per override rather than one on every capacity
                # tick, and status=="Discharging" keeps it from fighting a top-up in progress.
                ACTION=="change", SUBSYSTEM=="power_supply", KERNEL=="BAT0", ATTR{status}=="Discharging", ATTR{charge_control_end_threshold}!="80", ATTR{charge_control_start_threshold}="75", ATTR{charge_control_end_threshold}="80"
              '';
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

            # Anything not in intelHybridModels (modules/power.nix) is skipped
            # — the daemon would just exit there.
            cpu_model=$(awk -F: '/^model[[:space:]]*:/ { gsub(/ /, "", $2); print $2; exit }' /proc/cpuinfo)
            case "$cpu_model" in
            ${
              lib.concatMapStringsSep " | " toString (
                lib.sort (a: b: a < b) (lib.concatLists (lib.attrValues intelHybridModels))
              )
            })
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
                text =
                  "# managed-by: stubbe battery-power\n" + lib.generators.toINI { } { Unit.ConditionACPower = true; };
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
              text =
                "# managed-by: stubbe logind-lid\n"
                + lib.generators.toINI { } {
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
      };
    };
}
