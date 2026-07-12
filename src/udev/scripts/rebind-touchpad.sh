#!/usr/bin/env bash
# Rebind the i2c-hid touchpad after a Thunderbolt dock undock.
#
# See src/udev/rules.d/90-touchpad-rebind.rules for the full why: on
# staggio (Lunar Lake) the SNSL0028:00 touchpad stays enumerated but emits
# zero events after undock until its i2c_hid_acpi driver is rebound.
#
# Shared by both deploy paths:
#   - NixOS: systemd.services.touchpad-rebind in modules/nixos/udev.nix
#     runs this body via `script`.
#   - non-NixOS: installed to /etc/udev/scripts/rebind-touchpad.sh and run
#     by /etc/systemd/system/touchpad-rebind.service.
# Both are pulled in by SYSTEMD_WANTS from the udev DRM-hotplug rule.
set -u

drv=/sys/bus/i2c/drivers/i2c_hid_acpi
dev=i2c-SNSL0028:00

# No-op on any host without this touchpad (the udev rule also guards, but
# the service may be invoked directly).
[ -e "$drv/$dev" ] || exit 0

# True once the rebound device exposes multitouch. On probe the i2c-hid
# driver sends a SET_REPORT to switch the device into touchpad (MT) mode;
# that i2c transfer can fail silently while the dock power rail is still
# unsettled, leaving the device in single-touch mode — the cursor moves but
# two-finger scroll is dead. ABS_MT_POSITION_X (code 53) in the input node's
# abs capability bitmask is the signal that MT mode actually took. The mask
# prints as space-separated 64-bit words, most-significant first; codes < 64
# (all the MT codes) live in the last (least-significant) word.
mt_back() {
  local f abs
  for f in "$drv/$dev"/*/input/input*/capabilities/abs; do
    [ -r "$f" ] || continue
    abs=$(awk '{print $NF}' "$f")
    [ -n "$abs" ] || continue
    if (( 0x$abs & (1 << 53) )); then return 0; fi
  done
  return 1
}

# Re-apply Hyprland's per-device touchpad config to every live instance.
# The unbind/bind above destroys and re-creates the input device, so the
# per-device block in src/hypr/hyprland.lua (scroll_method=2fg, natural_scroll,
# ...) must be reapplied or two-finger scroll stays dead. scripts/monitor.toggle.sh
# already reloads Hyprland on the undock DRM-hotplug, but that fires seconds
# before this async rebind re-creates the device, and the no-monitor undock
# (thunderbolt-remove fallback) never reaches that user-side reactor at all —
# so the reload has to happen here, once MT is confirmed back.
#
# Talk to Hyprland's request socket directly instead of going through hyprctl:
# the wire protocol is just the command string, and hyprctl is a home-manager
# per-user binary that isn't on this root service's PATH. Root reaches the
# user-owned socket via DAC_OVERRIDE. socat is on the service PATH (NixOS) or
# the system (FHS); absent → the `|| true` degrades to before.
reload_hypr() {
  local sock
  command -v socat >/dev/null 2>&1 || return 0
  for sock in /run/user/*/hypr/*/.socket.sock; do
    [ -S "$sock" ] || continue
    printf 'reload' | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1 || true
  done
}

# Rebind, then verify MT came back; retry with a growing settle if it didn't.
# A single unbind/bind with a fixed sleep loses the race when the probe lands
# before the bus settles. Worst case ~14s of sleeps, all in this background
# oneshot — never blocks the udev worker.
for settle in 2 3 4 5; do
  sleep "$settle"
  echo "$dev" > "$drv/unbind" 2>/dev/null || true
  echo "$dev" > "$drv/bind"   2>/dev/null || true
  sleep 1
  mt_back && break
done

# Reapply compositor scroll config now the device is back (even if the MT
# verify never passed — a reload is cheap and idempotent).
reload_hypr
exit 0
