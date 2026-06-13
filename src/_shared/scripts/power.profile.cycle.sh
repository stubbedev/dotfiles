#!/usr/bin/env bash
# Cycle the active power profile to the next one offered by
# power-profiles-daemon, wrapping around. Order and the active profile both
# come from a single `powerprofilesctl list` call — the active one is the
# line marked with "* ". Bound to the wayle custom-powerprofile left-click.
set -euo pipefail

# A single fork (the list call via process substitution); parsing is pure
# bash builtins. Header lines end in ":" ("* balanced:", "  power-saver:");
# property lines ("    PlatformDriver: x") have a value after the colon, so
# the "ends in :" test skips them. `read` splits tokens and trims leading
# whitespace; the active profile's line starts with "* ".
profiles=()
current=""
while IFS= read -r line; do
  [[ $line == *: ]] || continue
  read -r tok1 tok2 _ <<<"$line"
  if [[ $tok1 == "*" ]]; then
    name=${tok2%:}
    current=$name
  else
    name=${tok1%:}
  fi
  profiles+=("$name")
done < <(powerprofilesctl list)

[[ ${#profiles[@]} -gt 0 ]] || exit 0

# Next profile after the active one, wrapping to the first.
next=${profiles[0]}
for i in "${!profiles[@]}"; do
  if [[ ${profiles[i]} == "$current" ]]; then
    next=${profiles[$(((i + 1) % ${#profiles[@]}))]}
    break
  fi
done

exec powerprofilesctl set "$next"
