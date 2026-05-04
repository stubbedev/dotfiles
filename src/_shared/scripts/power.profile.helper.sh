#!/usr/bin/env bash
# Helper script to write CPU frequency scaling values
# This script is designed to be called via pkexec from the power-profile-fix service

set -euo pipefail

write_value() {
    local file="$1"
    local value="$2"

    if [ -f "$file" ]; then
        if ! printf '%s' "$value" > "$file"; then
            echo "write failed: $file <= $value" >&2
            return 1
        fi
    fi
}

governor_supported() {
    local policy="$1"
    local requested="$2"
    local available
    available=$(cat "$policy/scaling_available_governors" 2>/dev/null || echo "")
    [[ " $available " == *" $requested "* ]]
}

resolve_governor() {
    local policy="$1"
    local requested="$2"

    if governor_supported "$policy" "$requested"; then
        echo "$requested"
        return
    fi

    if [ "$requested" = "schedutil" ] && governor_supported "$policy" "powersave"; then
        echo "powersave"
        return
    fi

    if [ "$requested" = "performance" ] && governor_supported "$policy" "schedutil"; then
        echo "schedutil"
        return
    fi

    if governor_supported "$policy" "performance"; then
        echo "performance"
        return
    fi

    if governor_supported "$policy" "powersave"; then
        echo "powersave"
        return
    fi

    echo "$requested"
}

case "${1:-}" in
    set-governor)
        # Set governor for all CPUs
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            policy=$(dirname "$cpu")
            resolved=$(resolve_governor "$policy" "$2")
            write_value "$cpu" "$resolved"
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

            current_min_khz=$(cat "$policy/scaling_min_freq" 2>/dev/null || echo "$min_khz")

            # Kernel rejects scaling_max_freq below current scaling_min_freq.
            # Lower min first only when needed for downscaling.
            if [ "$current_min_khz" -gt "$max_cap_khz" ]; then
                write_value "$policy/scaling_min_freq" "$max_cap_khz"
            fi

            # Set max before final min so upscales (e.g. 70% -> 100%) do not
            # fail when the requested min is above the previous max.
            write_value "$policy/scaling_max_freq" "$max_cap_khz"
            write_value "$policy/scaling_min_freq" "$min_khz"
        done
        ;;
    set-policy-min)
        # Set per-policy min frequency as percentage of hardware max, leave max untouched
        # Args: <min_pct>
        min_pct="$2"
        for policy in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -d "$policy" ] || continue
            max_khz=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null || echo "")
            min_hw_khz=$(cat "$policy/cpuinfo_min_freq" 2>/dev/null || echo "")
            current_max_khz=$(cat "$policy/scaling_max_freq" 2>/dev/null || echo "")
            [ -n "$max_khz" ] || continue
            min_khz=$((max_khz * min_pct / 100))
            if [ -n "$min_hw_khz" ] && [ "$min_khz" -lt "$min_hw_khz" ]; then
                min_khz="$min_hw_khz"
            fi
            if [ -n "$current_max_khz" ] && [ "$min_khz" -gt "$current_max_khz" ]; then
                min_khz="$current_max_khz"
            fi
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
    set-all)
        # Apply all CPU settings in one pkexec call for minimal latency.
        # Args: <min_pct> <max_pct> <governor> <epp|none> <boost> <up_rate_us> <down_rate_us> <iowait_enable>
        min_pct="$2"
        max_pct="$3"
        governor="$4"
        epp="$5"
        boost="$6"
        up_rate="$7"
        down_rate="$8"
        iowait_enable="$9"

        # 1. Remove frequency caps first so the CPU can ramp immediately.
        for policy in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -d "$policy" ] || continue
            max_khz=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null || echo "")
            [ -n "$max_khz" ] || continue
            min_khz=$((max_khz * min_pct / 100))
            max_cap_khz=$((max_khz * max_pct / 100))
            if [ $min_khz -gt $max_cap_khz ]; then
                min_khz=$max_cap_khz
            fi
            current_min_khz=$(cat "$policy/scaling_min_freq" 2>/dev/null || echo "$min_khz")
            if [ "$current_min_khz" -gt "$max_cap_khz" ]; then
                write_value "$policy/scaling_min_freq" "$max_cap_khz"
            fi
            write_value "$policy/scaling_max_freq" "$max_cap_khz"
            write_value "$policy/scaling_min_freq" "$min_khz"
        done

        # 2. Intel P-state limits.
        write_value "/sys/devices/system/cpu/intel_pstate/min_perf_pct" "$min_pct"
        write_value "/sys/devices/system/cpu/intel_pstate/max_perf_pct" "$max_pct"

        # 3. Governor.
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            policy=$(dirname "$cpu")
            resolved=$(resolve_governor "$policy" "$governor")
            write_value "$cpu" "$resolved"
        done

        # 4. EPP (skip if caller passed "none").
        if [ "$epp" != "none" ]; then
            for cpu in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
                write_value "$cpu" "$epp"
            done
        fi

        # 5. Boost / turbo.
        if [ "$boost" = "1" ]; then
            write_value "/sys/devices/system/cpu/cpufreq/boost" "1"
            write_value "/sys/devices/system/cpu/intel_pstate/no_turbo" "0"
        else
            write_value "/sys/devices/system/cpu/cpufreq/boost" "0"
            write_value "/sys/devices/system/cpu/intel_pstate/no_turbo" "1"
        fi

        # 6. Schedutil tunables (written after governor is set so the files exist).
        if [ "$governor" = "schedutil" ]; then
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
        fi
        ;;
    *)
        echo "Usage: $0 {set-governor|set-epp|set-pstate-limits|set-policy-freqs|set-policy-min|set-schedutil|set-boost|set-all} <args>"
        exit 1
        ;;
esac
