#!/usr/bin/env bash
# Fix CPU frequency scaling for power-saver and balanced profiles
# This script adjusts CPU governor and frequency limits based on power profile
# Works in both intel_pstate active mode (with EPP) and passive mode (with governors)

set -euo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | systemd-cat -t power-profile-fix -p info
}

get_current_profile() {
  powerprofilesctl get 2>/dev/null || echo "unknown"
}

get_profile_priority() {
  local profile="$1"
  case "$profile" in
  power-saver) echo 1 ;;
  balanced) echo 2 ;;
  performance) echo 3 ;;
  *) echo 0 ;;
  esac
}

is_upscaling() {
  local current="$1"
  local new="$2"
  local current_priority=$(get_profile_priority "$current")
  local new_priority=$(get_profile_priority "$new")
  [[ $new_priority -gt $current_priority ]]
}

get_scaling_driver() {
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "unknown"
}

is_passive_mode() {
  local driver=$(get_scaling_driver)
  [[ "$driver" == "intel_cpufreq" ]]
}

get_helper_path() {
  # Try to find the helper script
  local script_dir="$(dirname "$(readlink -f "$0")")"
  local helper="$script_dir/power-profile-helper.sh"

  if [ -f "$helper" ]; then
    echo "$helper"
  else
    echo ""
  fi
}

set_governor() {
  local governor="$1"
  local helper=$(get_helper_path)

  log "Setting CPU governor to: $governor"

  if [ -n "$helper" ]; then
    pkexec "$helper" set-governor "$governor" 2>&1 | logger -t power-profile-fix || true
  fi
}

set_epp() {
  local epp="$1"
  local helper=$(get_helper_path)

  log "Setting EPP to: $epp"

  if [ -n "$helper" ]; then
    pkexec "$helper" set-epp "$epp" 2>&1 | logger -t power-profile-fix || true
  fi
}

set_pstate_limits() {
  local min_perf="$1"
  local max_perf="$2"
  local helper=$(get_helper_path)

  if [ -f /sys/devices/system/cpu/intel_pstate/min_perf_pct ] && [ -n "$helper" ]; then
    log "Setting Intel P-state limits: min=$min_perf%, max=$max_perf%"
    pkexec "$helper" set-pstate-limits "$min_perf" "$max_perf" 2>&1 | logger -t power-profile-fix || true
  fi
}

apply_profile_fix() {
  local profile="$1"

  if is_passive_mode; then
    # Passive mode: Use software governors (schedutil, ondemand, etc.)
    case "$profile" in
    power-saver)
      # Use powersave governor for maximum battery life
      # Let schedutil handle scaling - it's smarter than powersave
      set_governor "schedutil"
      set_pstate_limits 9 100
      set_epp "power" # Hint if available
      log "Applied fix for power-saver profile (governor: schedutil, min: 9%, max: 100%)"
      ;;
    balanced)
      # Use schedutil for responsive yet efficient scaling
      set_governor "schedutil"
      set_pstate_limits 15 100
      set_epp "balance_performance" # Hint if available
      log "Applied fix for balanced profile (governor: schedutil, min: 15%, max: 100%)"
      ;;
    performance)
      # Use performance governor for maximum responsiveness
      set_governor "performance"
      set_pstate_limits 25 100
      set_epp "performance" # Hint if available
      log "Applied performance profile (governor: performance, min: 25%, max: 100%)"
      ;;
    *)
      log "Unknown profile: $profile, skipping"
      ;;
    esac
  else
    # Active mode: Use EPP hints for HWP
    case "$profile" in
    power-saver)
      set_epp "balance_power"
      set_pstate_limits 9 100
      log "Applied fix for power-saver profile (EPP: balance_power, min: 9%, max: 100%)"
      ;;
    balanced)
      set_epp "balance_performance"
      set_pstate_limits 15 100
      log "Applied fix for balanced profile (EPP: balance_performance, min: 15%, max: 100%)"
      ;;
    performance)
      set_epp "performance"
      set_pstate_limits 25 100
      log "Applied performance profile (EPP: performance, min: 25%, max: 100%)"
      ;;
    *)
      log "Unknown profile: $profile, skipping"
      ;;
    esac
  fi
}

# If called with a profile argument, apply it once
if [ $# -gt 0 ]; then
  apply_profile_fix "$1"
  exit 0
fi

# Otherwise, monitor for changes
log "Starting power profile monitor"

# Apply fix for current profile on startup
current_profile=$(get_current_profile)
log "Current profile on startup: $current_profile"
apply_profile_fix "$current_profile"

# Monitor for profile changes using dbus-monitor
dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/net/hadess/PowerProfiles'" 2>/dev/null |
  while read -r line; do
    if echo "$line" | grep -q "ActiveProfile"; then
      sleep 0.5 # Brief delay to ensure the profile change is complete
      old_profile="$current_profile"
      new_profile=$(get_current_profile)

      if [[ "$old_profile" != "$new_profile" ]]; then
        log "Power profile changed from: $old_profile to: $new_profile"

        if is_upscaling "$old_profile" "$new_profile"; then
          log "Upscaling detected - applying changes immediately"
          apply_profile_fix "$new_profile"
        else
          case "$new_profile" in
          performance)
            delay=30 # Long delay for performance downscaling
            ;;
          balanced)
            delay=10 # Moderate delay for balanced downscaling
            ;;
          power-saver | *)
            delay=3 # Short delay for power-saver downscaling
            ;;
          esac

          log "Downscaling detected - waiting $delay seconds before applying changes to $new_profile"
          sleep $delay

          # Double check profile hasn't changed again during wait
          current_check=$(get_current_profile)
          if [[ "$current_check" == "$new_profile" ]]; then
            apply_profile_fix "$new_profile"
          else
            log "Profile changed again during downscale delay to: $current_check - skipping downscale"
          fi
        fi

        current_profile="$new_profile"
      fi
    fi
  done
