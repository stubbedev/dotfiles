#!/bin/bash

# Audio control script for PipeWire
# Usage: audio.control.sh [volume-up|volume-down|volume-mute|mic-mute]

ACTION="${1:-help}"

# Get the numeric ID of the first audio source using Python
get_default_source_id() {
    python3 << 'EOF'
import subprocess
import re

output = subprocess.check_output(['wpctl', 'status'], text=True)
lines = output.split('\n')

in_audio_sources = False

for i, line in enumerate(lines):
    # Set flag when we see "Audio"
    if line.strip() == 'Audio':
        in_audio_sources = True
        continue
    elif line.strip() == 'Video' or line.strip() == 'Settings':
        in_audio_sources = False
        continue
    
    # If in Audio section and we see "Sources:"
    if in_audio_sources and 'Sources:' in line:
        # Look at next lines for source IDs
        for j in range(i+1, min(i+10, len(lines))):
            next_line = lines[j]
            # Look for numeric IDs at start (after whitespace)
            match = re.search(r'\s+(\d+)\.', next_line)
            if match:
                print(match.group(1))
                exit(0)
            # Stop if we hit another section
            if 'Filters:' in next_line or 'Streams:' in next_line or 'Sinks:' in next_line:
                break
EOF
}

case "$ACTION" in
    volume-up)
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
        ;;
    volume-down)
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        ;;
    volume-mute)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        ;;
    mic-mute)
        SOURCE_ID=$(get_default_source_id)
        if [ -n "$SOURCE_ID" ]; then
            wpctl set-mute "$SOURCE_ID" toggle
        else
            echo "Error: Could not find audio source" >&2
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 [volume-up|volume-down|volume-mute|mic-mute]"
        exit 1
        ;;
esac
