#!/usr/bin/env bash
# Waybar module: surface treeman worktree processing state.
# `treeman status --format waybar` emits {text,tooltip,class} directly.
set -u

command -v treeman >/dev/null 2>&1 && treeman status --format waybar 2>/dev/null
