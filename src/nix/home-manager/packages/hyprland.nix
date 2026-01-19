# Hyprland compositor and related tools
{ pkgs, config, hyprland, hyprland-guiutils, hy3, systemInfo, ... }:
let
  inherit (config.lib.nixGL) wrap;
  guiutils = hyprland-guiutils.packages.${pkgs.system}.default;
  hyprlandPkg = hyprland.packages.${pkgs.system}.hyprland;
  nixGLPackages = config.targets.genericLinux.nixGL.packages;

  # Create custom Hyprland wrapper with runtime GPU detection
  # This is needed because Nix's mesa-libgbm doesn't include GBM backends
  hyprland-wrapped = pkgs.writeShellScriptBin "hyprland" ''
    # Set GBM/DRI paths to use system libraries (needed on non-NixOS)
    # Auto-detected: ${
      if systemInfo.isFedora then "Fedora (lib64)" else "Generic Linux (lib)"
    }
    export GBM_BACKENDS_PATH=/usr/${systemInfo.libPath}/gbm:/usr/lib/gbm
    export LIBGL_DRIVERS_PATH=/usr/${systemInfo.libPath}/dri:/usr/lib/dri

    # Detect GPU at runtime and use appropriate nixGL wrapper
    if [ -f /proc/driver/nvidia/version ]; then
      # NVIDIA GPU detected - find the actual nixGL binary
      NIXGL_BIN=$(ls ${nixGLPackages.nixGLNvidia}/bin/nixGLNvidia* 2>/dev/null | head -1)
      exec "$NIXGL_BIN" ${hyprlandPkg}/bin/hyprland "$@"
    else
      # Use Mesa (Intel/AMD)
      exec ${nixGLPackages.nixGLIntel}/bin/nixGLIntel ${hyprlandPkg}/bin/hyprland "$@"
    fi
  '';

  # Create start-hyprland wrapper that uses our wrapped hyprland
  # The watchdog monitors the wrapped hyprland process
  start-hyprland-wrapped = pkgs.writeShellScriptBin "start-hyprland" ''
    set -euo pipefail

    # Clean up dead Hyprland instance directories before starting
    # This prevents accumulation of stale runtime directories
    HYPR_DIR="/run/user/$(id -u)/hypr"

    if [ -d "$HYPR_DIR" ]; then
      for dir in "$HYPR_DIR"/*/; do
        # Skip if glob didn't match anything
        [ -d "$dir" ] || continue

        instance_name=$(basename "$dir")
        is_dead=false

        # Check if this instance has a lock file
        if [ -f "$dir/hyprland.lock" ]; then
          # Validate PID from lock file
          pid=$(cat "$dir/hyprland.lock" 2>/dev/null | grep -E '^[0-9]+$' || echo "")

          if [ -n "$pid" ]; then
            # Check if process exists and is actually hyprland
            if ps -p "$pid" -o comm= 2>/dev/null | grep -q "hyprland"; then
              # Process is alive and is hyprland - keep it
              continue
            else
              # PID doesn't exist or isn't hyprland
              is_dead=true
            fi
          else
            # Invalid PID in lock file
            is_dead=true
          fi
        else
          # No lock file means it's definitely dead
          is_dead=true
        fi

        if [ "$is_dead" = true ]; then
          echo "Cleaning up dead Hyprland instance: $instance_name"
          rm -rf "$dir" 2>/dev/null || true
        fi
      done
    fi

    # Add our wrapped Hyprland to PATH so start-hyprland can find it
    export PATH="${hyprland-wrapped}/bin:$PATH"

    # Use the official start-hyprland watchdog
    exec ${hyprlandPkg}/bin/start-hyprland "$@"
  '';
  # Create hyprctl wrapper with automatic instance signature detection
  # This fixes the issue where shells started before Hyprland restart have stale
  # HYPRLAND_INSTANCE_SIGNATURE values (e.g., in tmux sessions or long-running terminals)
  hyprctl-wrapped = pkgs.writeShellScriptBin "hyprctl" ''
    set -euo pipefail

    # Clean up dead Hyprland instances (only once per minute to avoid overhead)
    USER_ID=$(id -u)
    HYPR_DIR="/run/user/$USER_ID/hypr"
    CLEANUP_FLAG="/tmp/hyprland-cleanup-$USER_ID"
    CURRENT_TIME=$(date +%s)
    LAST_CLEANUP_TIME=0

    # Get last cleanup time safely
    if [ -f "$CLEANUP_FLAG" ]; then
      LAST_CLEANUP_TIME=$(stat -c %Y "$CLEANUP_FLAG" 2>/dev/null || echo 0)
    fi

    # Perform cleanup if more than 60 seconds have passed
    if [ $((CURRENT_TIME - LAST_CLEANUP_TIME)) -gt 60 ]; then
      if [ -d "$HYPR_DIR" ]; then
        for dir in "$HYPR_DIR"/*/; do
          # Skip if glob didn't match anything
          [ -d "$dir" ] || continue

          is_dead=false

          # Check if this instance has a lock file
          if [ -f "$dir/hyprland.lock" ]; then
            # Validate PID from lock file (must be a valid number)
            pid=$(cat "$dir/hyprland.lock" 2>/dev/null | grep -E '^[0-9]+$' || echo "")

            if [ -n "$pid" ]; then
              # Check if process exists and is actually hyprland
              if ! ps -p "$pid" -o comm= 2>/dev/null | grep -q "hyprland"; then
                # PID doesn't exist or isn't hyprland - mark as dead
                is_dead=true
              fi
            else
              # Invalid or missing PID in lock file
              is_dead=true
            fi
          else
            # No lock file means it's definitely dead
            is_dead=true
          fi

          # Clean up dead instance silently
          if [ "$is_dead" = true ]; then
            rm -rf "$dir" 2>/dev/null || true
          fi
        done
      fi

      # Update cleanup timestamp
      touch "$CLEANUP_FLAG" 2>/dev/null || true
    fi

    # Auto-detect the current active Hyprland instance
    # Find the most recent directory with a valid lock file
    CURRENT_INSTANCE=""

    if [ -d "$HYPR_DIR" ]; then
      # Find all lock files, sorted by modification time (most recent first)
      for lock_file in $(ls -t "$HYPR_DIR"/*/hyprland.lock 2>/dev/null); do
        # Validate the lock file contains a valid PID
        pid=$(cat "$lock_file" 2>/dev/null | grep -E '^[0-9]+$' || echo "")

        if [ -n "$pid" ]; then
          # Verify the process is actually running and is hyprland
          if ps -p "$pid" -o comm= 2>/dev/null | grep -q "hyprland"; then
            # Found a valid instance - extract the instance signature
            CURRENT_INSTANCE=$(dirname "$lock_file" | xargs basename)
            break
          fi
        fi
      done
    fi

    # Set the instance signature if we found a valid one
    if [ -n "$CURRENT_INSTANCE" ]; then
      export HYPRLAND_INSTANCE_SIGNATURE="$CURRENT_INSTANCE"
    fi
    # If no active instance found, fall back to existing env var (if any)

    # Call hyprctl
    exec ${hyprlandPkg}/bin/hyprctl "$@"
  '';

  # Create a package with both hyprland (lowercase) and Hyprland (uppercase) symlink
  # start-hyprland expects "Hyprland" but we prefer lowercase everywhere else
  hyprland-both-cases = pkgs.runCommand "hyprland-both-cases" { } ''
    mkdir -p $out/bin
    ln -s ${hyprland-wrapped}/bin/hyprland $out/bin/hyprland
    ln -s ${hyprland-wrapped}/bin/hyprland $out/bin/Hyprland
  '';

  # Create swaync wrapper that auto-detects the correct Wayland display
  swaync-wrapped = pkgs.writeShellScriptBin "swaync" ''
    # Auto-detect the correct Wayland display socket
    if [ -z "$WAYLAND_DISPLAY" ] || [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
      # Find the most recent wayland-* socket
      for socket in $(ls -t "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v ".lock"); do
        if [ -S "$socket" ]; then
          export WAYLAND_DISPLAY=$(basename "$socket")
          break
        fi
      done
    fi

    # Ensure GDK uses Wayland backend
    export GDK_BACKEND=wayland

    # Run swaync
    exec ${pkgs.swaynotificationcenter}/bin/swaync "$@"
  '';

in with pkgs; [
  # Custom wrapped Hyprland with GBM path fix (provides both hyprland and Hyprland)
  hyprland-both-cases

  # Hyprctl (Hyprland control CLI)
  hyprctl-wrapped

  # Hyprland Start Binary
  start-hyprland-wrapped

  # Hyprlock with nixGL wrapper
  (wrap hyprlock)

  # Hyprland GUI utilities (from flake input)
  (wrap guiutils)

  # Hyprland ecosystem
  (wrap hyprshot)
  hyprlang
  hyprkeys
  hypridle
  (wrap hyprpaper)
  hyprsunset
  (wrap hyprpicker)
  hyprcursor
  hyprpolkitagent
  hyprutils
  hyprprop
  (wrap hyprsysteminfo)
  hyprwayland-scanner

  # Wayland tools
  wlprop
  wayland-scanner
  wayland-utils
  (wrap xwayland)
  (wrap slurp) # Screen area selection tool for screensharing picker
  (wrap grim) # Screenshot utility (works with slurp)

  # Desktop components (GUI apps need wrapping)
  (wrap waybar)
  (wrap ashell)
  swaync-wrapped # Custom wrapper with Wayland display auto-detection
  (wrap rofi)
  (wrap bemenu)

  # Portals
  hyprwire
  hyprland-protocols
  xdg-desktop-portal
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-wlr

  # Clipboard
  wl-clip-persist
]
