#!/bin/bash

# Parse tmux sessions and format them as [session_name | windows] with bold for attached sessions
output=""
while IFS=: read -r name windows attached; do
    if [ "$attached" -eq 1 ]; then
        output+=" [ $name:$windows] "
    else
        output+=" [ $name:$windows] "
    fi
done < <(tmux list-sessions -F "#{session_name}:#{session_windows}:#{session_attached}" 2>/dev/null)

# Remove trailing space
output="${output% }"

# If no sessions, show nothing or a placeholder
if [ -z "$output" ]; then
  output=""
fi

echo "$output"

