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
    # Add our wrapped Hyprland to PATH so start-hyprland can find it
    export PATH="${hyprland-wrapped}/bin:$PATH"
    
    # Use the official start-hyprland watchdog
    exec ${hyprlandPkg}/bin/start-hyprland "$@"
  '';
  # Create hyprctl wrapper with automatic instance signature detection
  # This fixes the issue where shells started before Hyprland restart have stale
  # HYPRLAND_INSTANCE_SIGNATURE values (e.g., in tmux sessions or long-running terminals)
  hyprctl-wrapped = pkgs.writeShellScriptBin "hyprctl" ''
    # Auto-detect the current active Hyprland instance
    # Find the most recent directory with a valid lock file
    CURRENT_INSTANCE=$(ls -t /run/user/$(id -u)/hypr/*/hyprland.lock 2>/dev/null | head -1 | xargs dirname 2>/dev/null | xargs basename 2>/dev/null)
    
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
