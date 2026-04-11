#!/usr/bin/env bash
# Helper script to write CPU frequency scaling values
# This script is designed to be called via pkexec from the power-profile-fix service

set -euo pipefail

write_value() {
    local file="$1"
    local value="$2"

    if [ -f "$file" ] && [ -w "$file" ]; then
        echo "$value" > "$file"
    fi
}

case "${1:-}" in
    set-governor)
        # Set governor for all CPUs
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            write_value "$cpu" "$2"
        done
        ;;
    set-epp)
        # Set EPP for all CPUs
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            write_value "$cpu" "$2"
        done
        ;;
    set-pstate-limits)
        # Set Intel P-state min/max limits
        write_value "/sys/devices/system/cpu/intel_pstate/min_perf_pct" "$2"
        write_value "/sys/devices/system/cpu/intel_pstate/max_perf_pct" "$3"
        ;;
    set-policy-freqs)
        # Set per-policy min/max frequencies as percentage of hardware max
        # Args: <min_pct> <max_pct>
        min_pct="$2"
        max_pct="$3"
        for policy in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -d "$policy" ] || continue
            max_khz=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null || echo "")
            [ -n "$max_khz" ] || continue
            min_khz=$((max_khz * min_pct / 100))
            max_cap_khz=$((max_khz * max_pct / 100))
            # Ensure min does not exceed max
            if [ $min_khz -gt $max_cap_khz ]; then
                min_khz=$max_cap_khz
            fi
            write_value "$policy/scaling_min_freq" "$min_khz"
            write_value "$policy/scaling_max_freq" "$max_cap_khz"
        done
        ;;
    set-policy-min)
        # Set per-policy min frequency as percentage of hardware max, leave max untouched
        # Args: <min_pct>
        min_pct="$2"
        for policy in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -d "$policy" ] || continue
            max_khz=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null || echo "")
            [ -n "$max_khz" ] || continue
            min_khz=$((max_khz * min_pct / 100))
            write_value "$policy/scaling_min_freq" "$min_khz"
        done
        ;;
    set-schedutil)
        # Set schedutil tunables if governor is schedutil
        # Args: <up_rate_us> <down_rate_us> <iowait_boost_enable>
        up_rate="$2"
        down_rate="$3"
        iowait_enable="$4"
        for policy in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -d "$policy" ] || continue
            gov_file="$policy/scaling_governor"
            [ -f "$gov_file" ] || continue
            if [ "$(cat "$gov_file" 2>/dev/null)" != "schedutil" ]; then
                continue
            fi
            write_value "$policy/schedutil/up_rate_limit_us" "$up_rate"
            write_value "$policy/schedutil/down_rate_limit_us" "$down_rate"
            write_value "$policy/schedutil/iowait_boost_enable" "$iowait_enable"
        done
        ;;
    set-boost)
        # Enable (1) or disable (0) turbo/boost
        if [ "$2" = "1" ]; then
            write_value "/sys/devices/system/cpu/cpufreq/boost" "1"
            write_value "/sys/devices/system/cpu/intel_pstate/no_turbo" "0"
        else
            write_value "/sys/devices/system/cpu/cpufreq/boost" "0"
            write_value "/sys/devices/system/cpu/intel_pstate/no_turbo" "1"
        fi
        ;;
    *)
        echo "Usage: $0 {set-governor|set-epp|set-pstate-limits|set-policy-freqs|set-policy-min|set-schedutil|set-boost} <args>"
        exit 1
        ;;
esac
