#!/usr/bin/env bash

# React to display and lid events by reloading Hyprland's config.
#
# Hyprland's built-in monitor-rule reapplication on hotplug is unreliable
# (notably on Thunderbolt dock unplug): waybar surfaces stay bound to the
# departed output (renders as solid color), the cursor reverts to the
# default theme, and per-monitor scale/position can drift from monitors.conf.
# `hyprctl reload` rebinds layer-shell surfaces, reissues setcursor, and
# re-applies every `monitor =` rule in one shot — the only command observed
# to recover the session without restarting Hyprland.
#
# Why udev, not socket2:
#   Hyprland's own monitoradded/monitorremoved events on socket2 are
#   well-known to fire unreliably — see hyprwm/Hyprland#1341 ("~10% of
#   the time") and discussion #5644 which recommends udev DRM events as
#   the canonical hotplug signal. udev sees the kernel-level HOTPLUG=1
#   uevent for every DRM card connector change, with no compositor in
#   the path. The same script remains usable on any Wayland compositor.
#
# Loop guard:
#   `hyprctl reload` itself doesn't emit udev events, so unlike the
#   previous socket2 design we have no inherent feedback loop. The 1s
#   debounce remains to collapse the short udev burst the kernel emits
#   when multiple connectors flap together (common on dock unplug).
#
# Usage:
#   monitor.toggle.sh           one-shot reapply (manual / scripts)
#   monitor.toggle.sh daemon    long-running listener; reacts to DRM
#                               hotplug events from udev and to laptop
#                               lid toggles read from libinput

# Re-apply Hyprland's full config. Reloads monitors, layer-shell, cursor.
apply_reload() {
  hyprctl reload >/dev/null 2>&1 || true
}

# Re-apply the wallpaper to every monitor after a hotplug. wayle's
# `wallpaper set` (without --monitor) only paints the outputs live at the
# moment it runs, so a monitor connected later — notably an external display
# brought up by a dock — comes up blank. apply_reload re-binds the Hyprland
# outputs but does not touch wayle's wallpaper layer, so we re-issue the set
# here. The new output may not be registered in wayle the instant hyprctl
# reload returns, so retry briefly in the background (~3s) without blocking.
#
# WALLPAPER comes from the session env (modules/home/session-variables.nix,
# sourced from constants.paths.wallpaper — the single source of truth shared
# with wayle-launch). Fall back to the literal path for a bare shell that
# never imported the session vars.
WALLPAPER="${WALLPAPER:-$HOME/.stubbe/src/wallpapers/ballet.jpg}"

apply_wallpaper() {
  command -v wayle >/dev/null 2>&1 || return 0
  (
    n=0
    while [ $n -lt 12 ]; do
      if wayle wallpaper set "$WALLPAPER" --fit fill >/dev/null 2>&1; then
        break
      fi
      n=$((n + 1))
      sleep 0.25
    done
  ) &
}

# Put the current lid position in $LID ("open" / "closed"), straight from the
# firmware. Every read of this proc file re-evaluates the ACPI _LID method
# (button.lid_init_state=method), so it stays correct even when the kernel
# drops the SW_LID input edge — which it does after a dock cycle, see poll_lid.
#
# Sets a global rather than echoing, and matches with `case` rather than
# `grep | head | tr`, so a poll tick costs no process at all: the glob, the
# redirect and `read` are all builtins. The forked pipeline this replaced was
# 12ms of CPU every 2s — more than everything else in this daemon combined.
read_lid() {
  local f line
  LID=open
  for f in /proc/acpi/button/lid/*/state; do
    [ -r "$f" ] || continue
    read -r line <"$f" || continue
    case "$line" in
    *[Cc]losed*) LID=closed ;;
    esac
    return
  done
}

# Disable the built-in panel when the lid is closed. The open case is
# handled implicitly by apply_reload above, which re-applies the eDP rule
# from monitors.conf and brings the panel back to its configured state.
# apply_reload also settles the touchpad either way — hyprland.lua reads the
# lid itself at config time — so only the panel is forced here, and only to
# skip the wait for the next reload.
apply_lid() {
  # ACPI lid bind fires before /proc/acpi/button/lid/*/state updates on some
  # hardware (notably when docked via Thunderbolt). Brief sleep avoids reading
  # the previous lid state and toggling the wrong direction.
  sleep 0.3

  read_lid

  # On lid-close, disable eDP *and* re-pack the externals from 0,0 in a single
  # Lua pass. apply_reload (run before this in react) already re-enabled eDP
  # and auto-positioned the externals to its right; disabling eDP alone would
  # leave them stranded at a half-screen x offset. reflow_monitors(true) redoes
  # the whole layout with the panel gone, so the external no longer renders
  # offset by half. (`hyprctl keyword monitor "...,disable"` is rejected under
  # the Lua config — "keyword can't work with non-legacy parsers. Use eval." —
  # so drive it through the exposed Lua reflow_monitors instead.)
  if [ "$LID" = "closed" ]; then
    hyprctl eval "reflow_monitors(true)" >/dev/null 2>&1 || true
  fi
}

react() {
  apply_reload
  apply_lid
  apply_wallpaper
}

# Suspend when a DRM change leaves a closed-lid machine with no external
# display — the macOS "unplug the dock in clamshell mode and it goes to
# sleep" behaviour. logind can't do this: HandleLidSwitch* only fires on
# the lid switch edge, never on a later display change (systemd#7690).
# Also called on the lid-close edge from poll_lid, where logind is the one
# that has gone missing — see the wait there for why that cannot double up
# with logind's own suspend.
suspend_if_closed_undocked() {
  local c
  read_lid
  [ "$LID" = "closed" ] || return 0
  for c in /sys/class/drm/card*-*/status; do
    case "$c" in *eDP*) continue ;; esac
    [ "$(cat "$c" 2>/dev/null)" = "connected" ] && return 0
  done
  systemctl suspend >/dev/null 2>&1 || true
}

# Restart WirePlumber so it re-evaluates ALSA card availability after a
# dock/undock. Without this, HDMI/DP sinks tied to the dock can linger as
# unavailable or fail to reappear in pavucontrol until the next login.
#
# Cooldown: a dock brings its connectors up over several seconds, and a
# docked resume replays the whole burst — each spaced past the 1s event
# debounce, so one physical event could restart wireplumber 2-3 times.
# Repeated pipewire/wireplumber churn is what wedges the SOF HDMI codec
# (ELDV stuck, needs a snd_sof_pci_intel_lnl reload), so cap restarts to
# one per 30s window.
_last_wp_restart=0
restart_wireplumber() {
  local now
  now=$(date +%s)
  [ $((now - _last_wp_restart)) -lt 30 ] && return 0
  _last_wp_restart=$now
  systemctl --user restart wireplumber.service >/dev/null 2>&1 || true
}

# Park fd 9 on the lid switch's own evdev node, found by name so it survives
# input renumbering. Best effort: without it wait_lid just sleeps.
lid_fd=""

open_lid_fd() {
  local f name event
  for f in /sys/class/input/event*/device/name; do
    [ -r "$f" ] || continue
    read -r name <"$f" || continue
    case "$name" in
    *[Ll]id*[Ss]witch*) ;;
    *) continue ;;
    esac
    event=${f#/sys/class/input/}
    event=${event%%/*}
    exec 9<"/dev/input/$event" 2>/dev/null && lid_fd=9
    return 0
  done
}

# Block until the lid switch moves, giving up after $1 seconds.
#
# The evdev node stays silent while the lid sits still, so this parks on a
# blocking read: no timer, no wakeups, and it returns the moment a real SW_LID
# edge arrives. The timeout is the recovery path — when the firmware swallows
# that edge (see poll_lid) the node never becomes readable, the read expires
# and the caller falls back to asking _LID directly. So the device is only ever
# a hint that something moved; _LID stays the source of truth, which is why it
# does not matter that `read` is handed raw input_event bytes it never parses.
# Both halves are one builtin: nothing is forked per iteration.
wait_lid() {
  if [ -n "$lid_fd" ]; then
    read -r -t "$1" -N 1 -u 9 _
  else
    sleep "$1"
  fi
  return 0
}

# React to the laptop lid: wait on its switch, but trust only the firmware.
#
# The kernel only emits SW_LID when the state it reads back from _LID differs
# from the one it last reported. After a Thunderbolt dock cycle this machine's
# firmware stops tracking the lid across the notification: the close arrives,
# _LID still answers "open", the edge is swallowed and dmesg says "ACPI:
# button: The lid device is not compliant to SW_LID." (newer kernels: FW_BUG
# "Unexpected lid state reported by firmware"). Nothing downstream of the
# input layer then sees the lid at all — no libinput switch toggle, so no
# touchpad suspend, and no logind "Lid closed" either. Reading _LID again a
# moment later does return the right answer, so every iteration asks _LID
# rather than believing the switch. wait_lid still parks on the switch, which
# makes a working edge instant and costs nothing while the lid sits still; its
# 2s timeout is what catches the transitions the firmware swallowed, and that
# lag is invisible on a lid that is already shut.
poll_lid() {
  local prev
  read_lid
  prev=$LID
  while wait_lid 2; do
    read_lid
    [ "$LID" = "$prev" ] && continue
    prev=$LID
    react

    # Suspending on a lid close with no external display is logind's job, but
    # logind is edge-driven too, so the same swallowed edge leaves the machine
    # awake in a bag. Wait before stepping in: when the edge did get through,
    # logind suspended within milliseconds and this line is never reached.
    # Still awake 5s after the lid shut means nothing else is going to do it,
    # so there is no double suspend to race with.
    if [ "$LID" = "closed" ]; then
      sleep 5
      suspend_if_closed_undocked
    fi
  done
}

# Watch libinput for the touchpad's own resume.
#
# When the lid switch does reach libinput, closing the lid makes it
# suspend the i2c-hid pad; the pad is re-added on lid open *after* the
# switch toggle, so the apply_reload that poll_lid fires lands too early and
# the per-device block (src/hyprland/hyprland.lua hl.device{ scroll_method = "2fg" })
# is dropped when the pad comes back — cursor moves, two-finger scroll dead.
# --verbose surfaces libinput's own "lid: resume touchpad" debug line, which is
# the actual "pad is live again" edge, so reload on that instead of guessing a
# settle delay. Same reason applies after an undock that never rebinds the
# driver (thinkpad_acpi port-replicator undock emits no DRM hotplug and no
# thunderbolt remove, so touchpad-rebind.service never runs).
listen_lid() {
  command -v libinput >/dev/null 2>&1 || return 0
  # Respawn if libinput exits, so a transient backend hiccup doesn't
  # silently kill lid handling for the rest of the session.
  while true; do
    stdbuf -oL libinput debug-events --verbose 2>/dev/null \
      | grep --line-buffered -i 'lid: resume touchpad' \
      | while IFS= read -r _; do
        apply_reload
      done
    sleep 2
  done
}

listen_events() {
  local last_action=0

  # Initial sync so reality matches config after a Hyprland (re)start.
  react

  # Before forking the pollers: fd 9 is inherited by them.
  open_lid_fd

  # Watch the lid and the touchpad resume alongside the DRM hotplug loop.
  poll_lid &
  local poll_pid=$!
  listen_lid &
  local lid_pid=$!
  trap 'kill "$poll_pid" "$lid_pid" 2>/dev/null' EXIT INT TERM

  # udevadm emits one HOTPLUG=1 property line per DRM hotplug uevent.
  # Process substitution keeps `last_action` in this shell rather than
  # the subshell that a pipe would create.
  while IFS= read -r line; do
    [ "$line" = "HOTPLUG=1" ] || continue

    now=$(date +%s)
    if [ $((now - last_action)) -lt 1 ]; then
      continue
    fi
    react
    restart_wireplumber
    suspend_if_closed_undocked
    last_action=$(date +%s)
  done < <(udevadm monitor --property --udev --subsystem-match=drm 2>/dev/null)
}

if [ "${1:-}" = "daemon" ]; then
  listen_events
else
  react
fi
