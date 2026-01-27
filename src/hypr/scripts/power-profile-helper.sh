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
    *)
        echo "Usage: $0 {set-governor|set-epp|set-pstate-limits} <args>"
        exit 1
        ;;
esac
