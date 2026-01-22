# Hyprland compositor and related tools
{ pkgs, config, hyprland, hyprland-guiutils, hy3, systemInfo, ... }:
let
  inherit (config.lib.nixGL) wrap;
  guiutils = hyprland-guiutils.packages.${pkgs.system}.default;
  hyprlandPkg = hyprland.packages.${pkgs.system}.hyprland;
  nixGLPackages = config.targets.genericLinux.nixGL.packages;

  # Create custom Hyprland wrapper with build-time GPU detection
  # This is needed because Nix's mesa-libgbm doesn't include GBM backends
  # The nixGL wrapper is pre-selected in systemInfo based on GPU detection
  hyprland-wrapped = pkgs.writeShellScriptBin "hyprland" (''
    # Set GBM/DRI paths to use system libraries (needed on non-NixOS)
    # Auto-detected: ${
      if systemInfo.isFedora then "Fedora (lib64)" else "Generic Linux (lib)"
    }
    export GBM_BACKENDS_PATH=/usr/${systemInfo.libPath}/gbm:/usr/lib/gbm
    export LIBGL_DRIVERS_PATH=/usr/${systemInfo.libPath}/dri:/usr/lib/dri

    # GPU detected at build time: ${if systemInfo.hasNvidia then "NVIDIA" else "Intel/Mesa"}
    # Using wrapper: ${systemInfo.nixGLWrapper}
  '' + (if systemInfo.hasNvidia then ''
    # NVIDIA: Find the versioned binary (e.g., nixGLNvidia-560.35.03)
    NIXGL_BIN=$(ls ${systemInfo.nixGLWrapper}/bin/nixGLNvidia* 2>/dev/null | head -1)
    exec "$NIXGL_BIN" ${hyprlandPkg}/bin/hyprland "$@"
  '' else ''
    # Intel/AMD: Use nixGLIntel directly
    exec ${systemInfo.nixGLWrapper}/bin/nixGLIntel ${hyprlandPkg}/bin/hyprland "$@"
  ''));

  # Create start-hyprland wrapper that uses our wrapped hyprland
  # The watchdog monitors the wrapped hyprland process
  start-hyprland-wrapped = pkgs.writeShellScriptBin "start-hyprland" ''
    # Ensure session PATH includes user and flatpak bins
    desired_paths=(
      "$HOME/.cargo/bin"
      "$HOME/.nix-profile/bin"
      "$HOME/.local/bin"
      "$HOME/.local/share/flatpak/exports/bin"
      "/var/lib/flatpak/exports/bin"
      "/usr/local/bin"
      "/usr/bin"
      "/bin"
    )
    prefix_paths=""
    for desired_path in "''${desired_paths[@]}"; do
      case ":$PATH:" in
        *":${desired_path}:"*) ;;
        *)
          if [ -z "$prefix_paths" ]; then
            prefix_paths="$desired_path"
          else
            prefix_paths="$prefix_paths:$desired_path"
          fi
          ;;
      esac
    done
    if [ -n "$prefix_paths" ]; then
      export PATH="$prefix_paths:$PATH"
    fi

    # Add our wrapped Hyprland to PATH so start-hyprland can find it
    export PATH="${hyprland-wrapped}/bin:$PATH"
    
    # Ensure we have the Hyprland binary available (both cases)
    # start-hyprland looks for "Hyprland" with capital H
    export PATH="${hyprland-both-cases}/bin:$PATH"
    
    # Use the official start-hyprland watchdog
    exec ${hyprlandPkg}/bin/start-hyprland "$@"
  '';
  # Create hyprctl wrapper with automatic instance signature detection
  # This fixes the issue where shells started before Hyprland restart have stale
  # HYPRLAND_INSTANCE_SIGNATURE values (e.g., in tmux sessions or long-running terminals)
  hyprctl-wrapped = pkgs.writeShellScriptBin "hyprctl" ''
    # Auto-detect the current active Hyprland instance
    # Prefer instances with a listening control socket
    CURRENT_INSTANCE=""

    for lockfile in $(ls -t /run/user/$(id -u)/hypr/*/hyprland.lock 2>/dev/null); do
      instance_dir=$(dirname "$lockfile")
      instance_name=$(basename "$instance_dir")
      socket_path="$instance_dir/.socket.sock"

      if [ -S "$socket_path" ] && ss -xl | grep -q "$socket_path"; then
        CURRENT_INSTANCE="$instance_name"
        break
      fi
    done

    # Fallback to newest lock file if no listening socket found
    if [ -z "$CURRENT_INSTANCE" ]; then
      CURRENT_INSTANCE=$(ls -t /run/user/$(id -u)/hypr/*/hyprland.lock 2>/dev/null | head -1 | xargs dirname 2>/dev/null | xargs basename 2>/dev/null)
    fi

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
