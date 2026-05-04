#!/usr/bin/env bash
# Fix CPU frequency scaling for power-saver and balanced profiles
# This script adjusts CPU governor and frequency limits based on power profile
# Works in both intel_pstate active mode (with EPP) and passive mode (with governors)

set -euo pipefail

STARTUP_WARMUP_SECONDS=${STARTUP_WARMUP_SECONDS:-8}
STARTUP_WARMUP_MIN_PCT=${STARTUP_WARMUP_MIN_PCT:-28}
STARTUP_WARMUP_MAX_PCT=${STARTUP_WARMUP_MAX_PCT:-100}
APPLY_RETRIES=${APPLY_RETRIES:-6}
APPLY_RETRY_SLEEP_SECONDS=${APPLY_RETRY_SLEEP_SECONDS:-0.2}
HIGH_LOAD_RETRY_SECONDS=${HIGH_LOAD_RETRY_SECONDS:-8}
BALANCED_MIN_PCT=${BALANCED_MIN_PCT:-18}
BALANCED_MAX_PCT=${BALANCED_MAX_PCT:-90}
BALANCED_BOOST=${BALANCED_BOOST:-0}
BALANCED_EPP=${BALANCED_EPP:-balance_performance}
BALANCED_UP_RATE_US=${BALANCED_UP_RATE_US:-4000}
BALANCED_DOWN_RATE_US=${BALANCED_DOWN_RATE_US:-65000}
BALANCED_IOWAIT_BOOST=${BALANCED_IOWAIT_BOOST:-1}
CPU_HOT_TEMP_MILLIC=${CPU_HOT_TEMP_MILLIC:-85000}
BALANCED_HOT_MAX_PCT=${BALANCED_HOT_MAX_PCT:-80}
BALANCED_HOT_EPP=${BALANCED_HOT_EPP:-balance_power}
PKEXEC_CMD=(pkexec --disable-internal-agent)

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
  local current_priority
  local new_priority
  current_priority=$(get_profile_priority "$current")
  new_priority=$(get_profile_priority "$new")
  [[ $new_priority -gt $current_priority ]]
}

get_scaling_driver() {
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "unknown"
}

get_available_governors() {
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null || echo ""
}

get_available_epp_values() {
  cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_available_preferences 2>/dev/null || echo ""
}

has_word() {
  local haystack="$1"
  local needle="$2"
  [[ " $haystack " == *" $needle "* ]]
}

choose_governor() {
  local preferred="$1"
  local fallback="$2"
  local available

  available=$(get_available_governors)
  if has_word "$available" "$preferred"; then
    echo "$preferred"
    return
  fi
  if has_word "$available" "$fallback"; then
    echo "$fallback"
    return
  fi
  if has_word "$available" "schedutil"; then
    echo "schedutil"
    return
  fi
  if has_word "$available" "performance"; then
    echo "performance"
    return
  fi
  echo "$preferred"
}

choose_epp() {
  local preferred="$1"
  local fallback="$2"
  local available

  available=$(get_available_epp_values)
  if [ -z "$available" ]; then
    echo ""
    return
  fi
  if has_word "$available" "$preferred"; then
    echo "$preferred"
    return
  fi
  if has_word "$available" "$fallback"; then
    echo "$fallback"
    return
  fi
  if has_word "$available" "balance_power"; then
    echo "balance_power"
    return
  fi
  if has_word "$available" "balance_performance"; then
    echo "balance_performance"
    return
  fi
  if has_word "$available" "performance"; then
    echo "performance"
    return
  fi
  if has_word "$available" "power"; then
    echo "power"
    return
  fi
  echo ""
}

get_helper_path() {
  # Prefer invocation path so polkit rules tied to symlink paths still match.
  local script_dir helper resolved_dir resolved_helper

  script_dir="$(dirname "$0")"
  helper="$script_dir/power.profile.helper.sh"
  if [ -f "$helper" ]; then
    echo "$helper"
    return
  fi

  resolved_dir="$(dirname "$(readlink -f "$0")")"
  resolved_helper="$resolved_dir/power.profile.helper.sh"
  if [ -f "$resolved_helper" ]; then
    echo "$resolved_helper"
  else
    echo ""
  fi
}

set_governor() {
  local governor="$1"

  log "Setting CPU governor to: $governor"

  run_helper set-governor "$governor" || log "Failed to set governor to: $governor"
}

set_epp() {
  local epp="$1"

  if [ -z "$epp" ]; then
    log "No supported EPP value found, skipping"
    return
  fi

  log "Setting EPP to: $epp"

  run_helper set-epp "$epp" || log "Failed to set EPP to: $epp"
}

set_pstate_limits() {
  local min_perf="$1"
  local max_perf="$2"

  if [ -f /sys/devices/system/cpu/intel_pstate/min_perf_pct ]; then
    log "Setting Intel P-state limits: min=$min_perf%, max=$max_perf%"
    run_helper set-pstate-limits "$min_perf" "$max_perf" || log "Failed to set Intel P-state limits"
  fi
}

set_policy_freqs() {
  local min_pct="$1"
  local max_pct="$2"

  log "Setting policy freqs: min=${min_pct}%, max=${max_pct}%"
  run_helper set-policy-freqs "$min_pct" "$max_pct" || log "Failed to set policy freqs"
}

set_policy_min_freqs() {
  local min_pct="$1"

  log "Setting policy min freqs: min=${min_pct}%"
  run_helper set-policy-min "$min_pct" || log "Failed to set policy min freqs"
}

set_schedutil_tunables() {
  local up_rate_us="$1"
  local down_rate_us="$2"
  local iowait_enable="$3"

  log "Setting schedutil tunables: up=${up_rate_us}us down=${down_rate_us}us iowait=${iowait_enable}"
  run_helper set-schedutil "$up_rate_us" "$down_rate_us" "$iowait_enable" || log "Failed to set schedutil tunables"
}

set_boost() {
  local enable="$1"

  log "Setting turbo/boost to: $enable"
  run_helper set-boost "$enable" || log "Failed to set turbo/boost to: $enable"
}

run_helper() {
  local helper

  helper=$(get_helper_path)
  if [ -z "$helper" ]; then
    log "Helper script not found"
    return 1
  fi

  if ! "${PKEXEC_CMD[@]}" "$helper" "$@" 2>&1 | logger -t power-profile-fix; then
    log "Helper command failed: $*"
    return 1
  fi
}

is_floor_applied() {
  local min_pct="$1"
  local tolerance_khz=100000

  for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    local max_khz cur_min_khz target_min_khz
    [ -d "$policy" ] || continue
    max_khz=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null || echo "")
    cur_min_khz=$(cat "$policy/scaling_min_freq" 2>/dev/null || echo "")
    [ -n "$max_khz" ] || continue
    [ -n "$cur_min_khz" ] || continue
    target_min_khz=$((max_khz * min_pct / 100))
    if [ $((cur_min_khz + tolerance_khz)) -lt "$target_min_khz" ]; then
      return 1
    fi
  done

  return 0
}

keep_floor() {
  local min_pct="$1"
  local duration_s="$2"
  local elapsed=0
  while [ "$elapsed" -lt "$duration_s" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
    if ! is_floor_applied "$min_pct"; then
      log "Floor drifted during delay window, reapplying"
      set_policy_min_freqs "$min_pct"
      set_pstate_limits "$min_pct" 100
    fi
  done
}

enforce_min_floor() {
  local profile="$1"
  local min_pct="$2"
  local attempt

  for ((attempt = 1; attempt <= APPLY_RETRIES; attempt++)); do
    if is_floor_applied "$min_pct"; then
      return 0
    fi
    log "Floor below target for $profile (attempt ${attempt}/${APPLY_RETRIES}), reapplying min floor"
    set_policy_min_freqs "$min_pct"
    if [ -f /sys/devices/system/cpu/intel_pstate/min_perf_pct ]; then
      set_pstate_limits "$min_pct" 100
    fi
    sleep "$APPLY_RETRY_SLEEP_SECONDS"
  done

  log "Unable to fully enforce min floor for $profile after ${APPLY_RETRIES} attempts"
}

log_policy_state() {
  local policy="/sys/devices/system/cpu/cpufreq/policy0"
  local gov min max cur epp driver

  [ -d "$policy" ] || return
  gov=$(cat "$policy/scaling_governor" 2>/dev/null || echo "n/a")
  min=$(cat "$policy/scaling_min_freq" 2>/dev/null || echo "n/a")
  max=$(cat "$policy/scaling_max_freq" 2>/dev/null || echo "n/a")
  cur=$(cat "$policy/scaling_cur_freq" 2>/dev/null || echo "n/a")
  epp=$(cat "$policy/energy_performance_preference" 2>/dev/null || echo "n/a")
  driver=$(get_scaling_driver)
  log "Policy state driver=$driver gov=$gov min=${min}kHz max=${max}kHz cur=${cur}kHz epp=$epp"
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

get_max_temp_millic() {
  local max_temp=0
  local temp

  for zone in /sys/class/thermal/thermal_zone*; do
    [ -f "$zone/temp" ] || continue
    temp=$(cat "$zone/temp" 2>/dev/null || echo "")
    [[ "$temp" =~ ^[0-9]+$ ]] || continue
    if [ "$temp" -gt "$max_temp" ]; then
      max_temp="$temp"
    fi
  done

  echo "$max_temp"
}

is_hot() {
  local max_temp
  max_temp=$(get_max_temp_millic)
  [ "$max_temp" -ge "$CPU_HOT_TEMP_MILLIC" ]
}

get_profile_min_pct() {
  local profile="$1"
  case "$profile" in
  power-saver) echo 8 ;;
  balanced) echo "$BALANCED_MIN_PCT" ;;
  performance) echo 35 ;;
  *) echo 8 ;;
  esac
}

# Apply only the minimum frequency floor immediately to prevent 400MHz during
# the delay window that follows a profile change. Does not touch governor or EPP.
apply_min_floor() {
  local profile="$1"
  local min_pct
  min_pct=$(get_profile_min_pct "$profile")
  log "Applying min freq floor for $profile: ${min_pct}%"
  set_policy_min_freqs "$min_pct"
  if [ -f /sys/devices/system/cpu/intel_pstate/min_perf_pct ]; then
    set_pstate_limits "$min_pct" 100
  fi
  enforce_min_floor "$profile" "$min_pct"
  log_policy_state
}

apply_profile_fix() {
  local profile="$1"

  local gov_pref="schedutil"
  local gov_fallback="powersave"
  local epp_pref="balance_power"
  local epp_fallback="balance_performance"
  local gov
  local epp
  local epp_arg
  local min_pct=8
  local max_pct=100
  local boost=1
  local up_rate=4000
  local down_rate=65000
  local iowait=1

  case "$profile" in
  power-saver)
    gov_pref="schedutil"
    gov_fallback="schedutil"
    epp_pref="power"
    epp_fallback="balance_power"
    min_pct=8
    max_pct=60
    boost=0
    up_rate=40000
    down_rate=120000
    iowait=0
    ;;
  balanced)
    gov_pref="schedutil"
    gov_fallback="schedutil"
    epp_pref="$BALANCED_EPP"
    epp_fallback="balance_power"
    min_pct=$BALANCED_MIN_PCT
    max_pct=$BALANCED_MAX_PCT
    boost=$BALANCED_BOOST
    up_rate=$BALANCED_UP_RATE_US
    down_rate=$BALANCED_DOWN_RATE_US
    iowait=$BALANCED_IOWAIT_BOOST
    if is_hot; then
      max_pct=$BALANCED_HOT_MAX_PCT
      epp_pref="$BALANCED_HOT_EPP"
      log "Thermal guard active for balanced: max=${max_pct}% epp=${epp_pref}"
    fi
    ;;
  performance)
    gov_pref="performance"
    gov_fallback="performance"
    epp_pref="performance"
    epp_fallback="balance_performance"
    min_pct=35
    max_pct=100
    boost=1
    up_rate=2000
    down_rate=15000
    iowait=1
    ;;
  *)
    log "Unknown profile: $profile, skipping"
    return
    ;;
  esac

  gov=$(choose_governor "$gov_pref" "$gov_fallback")
  epp=$(choose_epp "$epp_pref" "$epp_fallback")
  epp_arg="${epp:-none}"

  # Single pkexec call: freq caps are removed first inside the helper so the
  # CPU can ramp immediately, then governor/EPP/boost/schedutil follow.
  log "Applying profile=$profile gov=$gov epp=$epp_arg min=${min_pct}% max=${max_pct}% boost=$boost"
  run_helper set-all "$min_pct" "$max_pct" "$gov" "$epp_arg" "$boost" "$up_rate" "$down_rate" "$iowait"
  enforce_min_floor "$profile" "$min_pct"
  log "Applied profile=$profile gov=$gov epp=$epp_arg min=${min_pct}% max=${max_pct}% boost=$boost"
  log_policy_state
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
    if [[ "$line" == *"ActiveProfile"* ]]; then
      sleep 0.2 # Brief delay to ensure the profile change is complete
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
            delay=8
            ;;
          balanced)
            delay=2
            ;;
          power-saver | *)
            delay=1
            ;;
          esac

          # Immediately apply a min freq floor so the CPU doesn't sit at
          # 400MHz (cpuinfo_min_freq) while we wait for the delay to expire.
          # PPD resets scaling_min_freq to cpuinfo_min_freq on profile changes;
          # this bridges that gap.
          floor_min_pct=$(get_profile_min_pct "$new_profile")
          apply_min_floor "$new_profile"
          log "Downscaling detected - waiting $delay seconds before applying changes to $new_profile"
          keep_floor "$floor_min_pct" "$delay" &
          floor_pid=$!
          sleep $delay
          kill "$floor_pid" 2>/dev/null || true
          wait "$floor_pid" 2>/dev/null || true

          # Double check profile hasn't changed again during wait
          current_check=$(get_current_profile)
          if [[ "$current_check" != "$new_profile" ]]; then
            log "Profile changed again during downscale delay to: $current_check - skipping downscale"
            continue
          fi

          if is_high_load; then
            log "High load detected; deferring full apply for $new_profile by ${HIGH_LOAD_RETRY_SECONDS}s"
            (
              sleep "$HIGH_LOAD_RETRY_SECONDS"
              if [[ "$(get_current_profile)" = "$new_profile" ]] && ! is_high_load; then
                log "Retrying deferred apply for $new_profile"
                apply_profile_fix "$new_profile"
              fi
            ) &
            current_profile="$new_profile"
            continue
          fi

          apply_profile_fix "$new_profile"
        fi

        current_profile="$new_profile"
      fi
    fi
  done
