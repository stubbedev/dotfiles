#!/usr/bin/env bash

# Reapply Hyprland's per-device input config after the session unlocks.
#
# Symptom: on staggio (Lunar Lake, i2c-hid SNSL0028:00 touchpad) two-finger
# scroll is dead after unlocking, while the cursor still moves.
#
# Cause: closing the lid makes libinput suspend the pad (the hyprland log shows
# "lid: suspending touchpad"). scripts/monitor.toggle.sh's lid daemon runs
# `hyprctl reload` on the lid switch_toggle event, but that fires *before*
# libinput's later "lid: resume touchpad", so the per-device block reapplied by
# the reload (src/hypr/hyprland.lua hl.device{ scroll_method = "2fg", ... }) is
# dropped when the pad resumes. Single-touch survives (cursor moves) but the MT
# scroll config is gone. The undock case is handled by rebind-touchpad.sh; this
# handles the lock/lid case from the user side (no root, no driver rebind — the
# pad stays MT-capable, only the compositor config is lost).
#
# Fix: reload once more after the session unlocks. Unlock always happens after
# the lid resume has settled (you open the lid, then type the password), so the
# reload here lands on a live, resumed pad and reapplies scroll_method. Also
# covers a lid-less lock/unlock (SUPER+escape then unlock).
#
# Trigger: wayle reports unlock to logind via SetLockedHint(false). A password
# unlock emits no logind `Unlock` signal (that path is for loginctl/idle), only
# a LockedHint property change — so watch the session's PropertiesChanged and
# reload on the locked -> unlocked edge. `.../session/auto` resolves to this
# session, same as wayle's own logind proxy.
set -u

command -v dbus-monitor >/dev/null 2>&1 || exit 0
command -v busctl >/dev/null 2>&1 || exit 0

sess=/org/freedesktop/login1/session/auto

# 0 = locked, 1 = unlocked. busctl prints "b true" / "b false".
is_locked() {
  case "$(busctl --system get-property org.freedesktop.login1 "$sess" \
    org.freedesktop.login1.Session LockedHint 2>/dev/null)" in
  *true*) return 0 ;;
  *) return 1 ;;
  esac
}

# Assume locked at start: the shell self-locks on boot (lock-on-start), so the
# first real edge we care about is the transition to unlocked.
prev=locked

dbus-monitor --system \
  "type='signal',interface='org.freedesktop.login1.Session',member='PropertiesChanged'" \
  2>/dev/null | while IFS= read -r line; do
  # One check per signal, not per output line.
  case "$line" in *"member=PropertiesChanged"*) ;; *) continue ;; esac

  if is_locked; then
    prev=locked
    continue
  fi

  # Unlocked now. Reload only on the locked -> unlocked edge so unrelated
  # PropertiesChanged (idle hint, active toggles) don't spam reloads.
  if [ "$prev" = locked ]; then
    prev=unlocked
    # Small settle: the lock surface is torn down and input restored right
    # around the hint flip; reload just after so it reapplies onto live devices.
    sleep 0.5
    hyprctl reload >/dev/null 2>&1 || true
  fi
done
