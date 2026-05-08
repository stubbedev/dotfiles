#!/usr/bin/env bash

# Locate the tmux server socket. tmux picks $TMUX_TMPDIR, then $TMPDIR, then
# /tmp — but waybar is launched without TMPDIR set, so it would always look
# in /tmp even when the server lives under $XDG_RUNTIME_DIR. Probe both common
# locations so the same script works whether tmux was started by a NixOS
# system service (often XDG_RUNTIME_DIR) or a plain home-manager shell (/tmp).
uid=$(id -u)
sessions=""
for sock in \
    "${TMUX_TMPDIR:-}/tmux-$uid/default" \
    "${TMPDIR:-}/tmux-$uid/default" \
    "${XDG_RUNTIME_DIR:-/run/user/$uid}/tmux-$uid/default" \
    "/tmp/tmux-$uid/default"; do
    [ -S "$sock" ] || continue
    sessions=$(tmux -S "$sock" list-sessions -F "#{session_name}:#{session_windows}:#{session_attached}" 2>/dev/null) || sessions=""
    [ -n "$sessions" ] && break
done

# Parse tmux sessions and format them as [session_name | windows] with bold for attached sessions
output=""
while IFS=: read -r name windows attached; do
    [ -z "$name" ] && continue
    if [ "$attached" -eq 1 ]; then
        output+="[ $name:$windows] "
    else
        output+="[ $name:$windows] "
    fi
done <<< "$sessions"

# Remove trailing space
output="${output% }"

# If no sessions, show nothing or a placeholder
if [ -z "$output" ]; then
  output=" "
fi

echo "$output"
