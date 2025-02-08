#!/usr/bin/env bash

# Get the action (lid-close or lid-open) passed as an argument
action=$1

# Get the list of all active monitors
monitors=$(hyprctl monitors | grep "active" | awk '{print $1}')

# Get the current workspace number
current_workspace=$(hyprctl activeworkspace)

# Get the current active monitor (assuming first monitor in the list is active)
current_monitor=$(hyprctl activemonitor)

# Find the next monitor in the list (wrap around to the first if at the end)
monitor_array=($monitors)
next_monitor=${monitor_array[1]} # Default to the second monitor
for i in "${!monitor_array[@]}"; do
  if [ "${monitor_array[$i]}" == "$current_monitor" ]; then
    next_monitor="${monitor_array[$((i + 1))]}"
    if [ "$i" -eq "$((${#monitor_array[@]} - 1))" ]; then
      next_monitor="${monitor_array[0]}" # Wrap around to the first monitor
    fi
    break
  fi
done

# Find the built-in monitor dynamically (usually eDP or LVDS)
builtin_monitor=$(hyprctl monitors | grep -i "eDP" | awk '{print $1}')
if [ -z "$builtin_monitor" ]; then
  builtin_monitor=$(hyprctl monitors | grep -i "LVDS" | awk '{print $1}')
fi

if [ "$action" == "close" ]; then
  # Move the current workspace to the next active monitor
  hyprctl workspace "$current_workspace" # Just in case, reselect the workspace
  hyprctl monitor "$next_monitor"        # Move workspace to the next monitor

  # Deactivate the built-in laptop screen
  if [ -n "$builtin_monitor" ]; then
    hyprctl monitor "$builtin_monitor" off # Deactivate the built-in screen
  else
    echo "Built-in monitor not found!"
  fi
elif [ "$action" == "open" ]; then
  # Reactivate the built-in monitor
  if [ -n "$builtin_monitor" ]; then
    hyprctl monitor "$builtin_monitor" on # Reactivate the built-in screen
  else
    echo "Built-in monitor not found!"
  fi

  # Optionally, move the workspace back to the laptop monitor
  hyprctl workspace "$current_workspace" # Just in case, reselect the workspace
  hyprctl monitor "$builtin_monitor"     # Move workspace back to the built-in screen
else
  echo "Invalid action. Use 'close' or 'open'."
fi
