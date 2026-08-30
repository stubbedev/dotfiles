_: {
  # Not covered: the systemd wiring (timer cadence, the .path unit) and the
  # real EC's rejection of a start > end write — both need a machine, not a
  # sandbox. What is covered is every branch that decides the numbers.
  perSystem =
    { pkgs, ... }:
    {
      checks.power-source =
        pkgs.runCommand "check-power-source"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.gawk
            ];
          }
          ''
            set -euo pipefail

            root="$(mktemp -d)"
            export POWER_SOURCE_SUPPLY_DIR="$root/ps"
            export POWER_SOURCE_STATE_DIR="$root/state"
            export POWER_SOURCE_RUNTIME_DIR="$root/run"
            mkdir -p "$root/ps/AC" "$root/ps/BAT0" "$root/state" "$root/run" "$root/bin"

            printf 'Mains' >"$root/ps/AC/type"
            printf 'Battery' >"$root/ps/BAT0/type"

            # Stub PPD: records every call, and answers `list` with the three
            # profiles this laptop actually exposes.
            ppd_log="$root/ppd.log"
            : >"$ppd_log"
            cat >"$root/bin/powerprofilesctl" <<'STUB'
            #!/bin/sh
            echo "$@" >>"$PPD_LOG"
            case "$1" in
            list) printf '  performance:\n  balanced:\n* power-saver:\n' ;;
            esac
            STUB
            sed -i 's/^            //' "$root/bin/powerprofilesctl"
            chmod +x "$root/bin/powerprofilesctl"
            export PATH="$root/bin:$PATH"
            export PPD_LOG="$ppd_log"

            plug()   { printf '1' >"$root/ps/AC/online"; }
            unplug() { printf '0' >"$root/ps/AC/online"; }
            caps()   { printf '%s/%s' \
                         "$(cat "$root/ps/BAT0/charge_control_start_threshold")" \
                         "$(cat "$root/ps/BAT0/charge_control_end_threshold")"; }
            reset()  { printf '75' >"$root/ps/BAT0/charge_control_start_threshold"
                       printf '80' >"$root/ps/BAT0/charge_control_end_threshold"; }
            sets()   { grep -c '^set ' "$ppd_log" || true; }

            fail() { echo "FAIL: $1" >&2; exit 1; }

            # $1 = "dow hh mm", $2 = expected start/end, $3 = what it proves
            run() {
              POWER_SOURCE_NOW="$1" bash ${pkgs.writeText "power-source.sh" pkgs.stubbe.powerSourceScript}
              got="$(caps)"
              [ "$got" = "$2" ] || fail "$3 — expected $2, got $got"
              echo "ok: $3"
            }

            reset
            plug

            run "1 16 00" "75/80" "no history at all means no prediction, so hold at 80"
            [ "$(sets)" = 1 ] || fail "first run should pick a profile, got $(sets) calls"
            grep -qx 'set performance' "$ppd_log" || fail "on AC the profile should be performance"
            echo "ok: the first run lands on the AC profile"

            # Four Monday unplugs between 16:45 and 17:30.
            printf '1 1020\n1 1035\n1 1005\n1 1050\n' >"$root/state/unplugs"

            run "1 16 00" "95/100" "an hour before the usual Monday unplug, top up"
            run "1 10 00" "75/80"  "seven hours before it, hold — and come back down"
            run "1 23 00" "75/80"  "after the last unplug of the day, hold overnight"
            run "3 16 00" "95/100" "no Wednesday history falls back to every weekday"

            [ "$(sets)" = 1 ] || fail "the timer must not restomp the profile, got $(sets) calls"
            echo "ok: a profile picked by hand survives runs with no power-source change"

            # The manual override wins regardless of the prediction.
            touch "$root/run/full-now"
            run "1 10 00" "95/100" "charge-to-full overrides a far-off prediction"

            # ... and does not survive the charger coming out. On battery the
            # script only records and exits, so the caps are left as the udev
            # rule would have set them.
            unplug
            reset
            run "2 17 10" "75/80" "on battery the script leaves the thresholds alone"
            grep -qx 'set power-saver' "$ppd_log" || fail "unplugging should drop to power-saver"
            echo "ok: unplugging drops the profile to power-saver"
            test ! -e "$root/run/full-now" || fail "unplug did not clear the charge-to-full flag"
            echo "ok: unplugging clears the charge-to-full flag"
            tail -n1 "$root/state/unplugs" | grep -qx '2 1030' \
              || fail "unplug was not recorded as Tuesday 17:10"
            echo "ok: the unplug is recorded against the right weekday and minute"

            touch "$out"
          '';
    };
}
