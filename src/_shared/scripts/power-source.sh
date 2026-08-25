#!/usr/bin/env bash
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
# Wired up by modules/nixos/power-source.nix (NixOS) and
# modules/activation/_privileged/setup-power-source.nix (everything else).
set -u

# ponytail: these five env vars are test seams, not configuration — they let
# modules/checks/power-source.nix point the script at a fake sysfs tree and a
# fixed clock. Nothing sets them in production.
supplies=${POWER_SOURCE_SUPPLY_DIR:-/sys/class/power_supply}
bat=${POWER_SOURCE_BAT:-$supplies/BAT0}
state=${POWER_SOURCE_STATE_DIR:-/var/lib/power-source}
runtime=${POWER_SOURCE_RUNTIME_DIR:-/run/battery-charge}
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

read -r dow hour minute <<<"${POWER_SOURCE_NOW:-$(date '+%u %H %M')}"
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
