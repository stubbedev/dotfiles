#!/usr/bin/env bash
# Fix CPU frequency scaling for power-saver and balanced profiles
# This script adjusts CPU governor and frequency limits based on power profile
# Works in both intel_pstate active mode (with EPP) and passive mode (with governors)

set -euo pipefail

STARTUP_WARMUP_SECONDS=${STARTUP_WARMUP_SECONDS:-75}
STARTUP_WARMUP_MIN_PCT=${STARTUP_WARMUP_MIN_PCT:-75}
STARTUP_WARMUP_MAX_PCT=${STARTUP_WARMUP_MAX_PCT:-100}

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

set_policy_freqs() {
  local min_pct="$1"
  local max_pct="$2"
  local helper=$(get_helper_path)

  if [ -n "$helper" ]; then
    log "Setting policy freqs: min=${min_pct}%, max=${max_pct}%"
    pkexec "$helper" set-policy-freqs "$min_pct" "$max_pct" 2>&1 | logger -t power-profile-fix || true
  fi
}

set_schedutil_tunables() {
  local up_rate_us="$1"
  local down_rate_us="$2"
  local iowait_enable="$3"
  local helper=$(get_helper_path)

  if [ -n "$helper" ]; then
    log "Setting schedutil tunables: up=${up_rate_us}us down=${down_rate_us}us iowait=${iowait_enable}"
    pkexec "$helper" set-schedutil "$up_rate_us" "$down_rate_us" "$iowait_enable" 2>&1 | logger -t power-profile-fix || true
  fi
}

set_boost() {
  local enable="$1"
  local helper=$(get_helper_path)

  if [ -n "$helper" ]; then
    log "Setting turbo/boost to: $enable"
    pkexec "$helper" set-boost "$enable" 2>&1 | logger -t power-profile-fix || true
  fi
}

apply_startup_warmup() {
  local profile="$1"

  case "$profile" in
  balanced | power-saver)
    log "Startup warmup for $profile: holding min freq at ${STARTUP_WARMUP_MIN_PCT}% for ${STARTUP_WARMUP_SECONDS}s"
    set_policy_freqs "$STARTUP_WARMUP_MIN_PCT" "$STARTUP_WARMUP_MAX_PCT"
    set_pstate_limits "$STARTUP_WARMUP_MIN_PCT" "$STARTUP_WARMUP_MAX_PCT"
    (
      sleep "$STARTUP_WARMUP_SECONDS"
      local active_profile
      active_profile=$(get_current_profile)
      if [[ "$active_profile" = "$profile" ]]; then
        log "Startup warmup complete; restoring defaults for $profile"
        apply_profile_fix "$profile"
      else
        log "Startup warmup complete; current profile is $active_profile, skipping revert"
      fi
    ) &
    ;;
  *)
    ;;
  esac
}

is_high_load() {
  local load cores
  load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo "0")
  cores=$(nproc 2>/dev/null || echo "1")
  # Return success if load >= 0.7 * cores
  awk -v l="$load" -v c="$cores" 'BEGIN { exit (l >= c*0.7 ? 0 : 1) }'
}

apply_profile_fix() {
  local profile="$1"

  # Defaults
  local gov="schedutil"
  local epp="balance_power"
  local min_pct=10
  local max_pct=100
  local boost=1

  if is_passive_mode; then
    case "$profile" in
    power-saver)
      gov="schedutil"
      epp="power"
      min_pct=10
      max_pct=70
      boost=0
      ;;
    balanced)
      gov="schedutil"
      epp="balance_performance"
      min_pct=30
      max_pct=100
      boost=1
      ;;
    performance)
      gov="performance"
      epp="performance"
      min_pct=85
      max_pct=100
      boost=1
      ;;
    *)
      log "Unknown profile: $profile, skipping"
      return
      ;;
    esac
  else
    case "$profile" in
    power-saver)
      gov="schedutil"
      epp="balance_power"
      min_pct=10
      max_pct=70
      boost=0
      ;;
    balanced)
      gov="schedutil"
      epp="balance_performance"
      min_pct=30
      max_pct=100
      boost=1
      ;;
    performance)
      gov="performance"
      epp="performance"
      min_pct=85
      max_pct=100
      boost=1
      ;;
    *)
      log "Unknown profile: $profile, skipping"
      return
      ;;
    esac
  fi

  set_governor "$gov"
  set_epp "$epp"
  set_policy_freqs "$min_pct" "$max_pct"
  set_pstate_limits "$min_pct" "$max_pct"
  set_boost "$boost"
  if [ "$gov" = "schedutil" ]; then
    case "$profile" in
    power-saver)
      set_schedutil_tunables 30000 80000 0
      ;;
    balanced)
      set_schedutil_tunables 20000 60000 0
      ;;
    performance)
      set_schedutil_tunables 5000 20000 1
      ;;
    esac
  fi
  log "Applied profile=$profile gov=$gov epp=$epp min=${min_pct}% max=${max_pct}% boost=$boost"
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
apply_startup_warmup "$current_profile"

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
          if [[ "$current_check" != "$new_profile" ]]; then
            log "Profile changed again during downscale delay to: $current_check - skipping downscale"
            continue
          fi

          if is_high_load; then
            log "Skipping downscale to $new_profile due to high load"
            continue
          fi

          apply_profile_fix "$new_profile"
        fi

        current_profile="$new_profile"
      fi
    fi
  done
