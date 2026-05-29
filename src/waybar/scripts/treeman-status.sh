#!/usr/bin/env bash

# Waybar module: surface treeman worktree processing state.
#
# treeman now renders the whole waybar object itself —
# `treeman status --format waybar` emits {text,tooltip,class} directly,
# so the grouping/escaping that used to live in jq here is gone.
#
# Customize the icons, labels, separators, hover header/row, and any
# custom formats under the `status:` block in ~/.config/treeman/config.yaml.
# See `treeman status --help` for the available --format values and the
# config-reference for the status: keys. With no config the bar text is
# `stable: N | up: N | down: N | failed: N`.

set -u

empty='{"text":"","tooltip":"","class":""}'

command -v treeman >/dev/null 2>&1 || { echo "$empty"; exit 0; }

# Only forward a well-formed object. Guards the version-skew window
# where an older treeman without `status` would print its help to
# stdout on the unknown command — which would otherwise garble the bar.
out=$(treeman status --format waybar 2>/dev/null)
case "$out" in
    \{*) printf '%s\n' "$out" ;;
    *) echo "$empty" ;;
esac
