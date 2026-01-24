# Hyprland compositor and related tools
{ pkgs, homeLib, hyprland, hyprland-guiutils, hy3, systemInfo, ... }:
let
  lib = pkgs.lib;
  guiutils = hyprland-guiutils.packages.${pkgs.system}.default;
  hyprlandPkg = hyprland.packages.${pkgs.system}.hyprland;

  gbmPaths = lib.unique [
    "/usr/lib64/gbm"
    "/usr/lib/gbm"
    "/run/opengl-driver/lib/gbm"
    "/run/opengl-driver-32/lib/gbm"
  ];

  driPaths = lib.unique [
    "/usr/lib64/dri"
    "/usr/lib/dri"
    "/run/opengl-driver/lib/dri"
    "/run/opengl-driver-32/lib/dri"
  ];

  # Create custom Hyprland wrapper with build-time GPU detection
  # This is needed because Nix's mesa-libgbm doesn't include GBM backends
  # The nixGL wrapper is pre-selected in systemInfo based on GPU detection
  hyprland-wrapped = homeLib.gfxNameWith "hyprland" ''
    # Set GBM/DRI paths to use system libraries (needed on non-NixOS)
    export GBM_BACKENDS_PATH=${lib.concatStringsSep ":" gbmPaths}
    export LIBGL_DRIVERS_PATH=${lib.concatStringsSep ":" driPaths}
  ''
    hyprlandPkg;

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
        *":''${desired_path}:"*) ;;
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

    # Ensure XDG_DATA_DIRS includes Flatpak/Nix desktop entries
    desired_data_dirs=(
      "$HOME/.local/share/flatpak/exports/share"
      "$HOME/.nix-profile/share"
      "/nix/var/nix/profiles/default/share"
      "/var/lib/flatpak/exports/share"
      "/usr/local/share"
      "/usr/share"
    )
    prefix_data_dirs=""
    for desired_dir in "''${desired_data_dirs[@]}"; do
      case ":$XDG_DATA_DIRS:" in
        *":''${desired_dir}:"*) ;;
        *)
          if [ -z "$prefix_data_dirs" ]; then
            prefix_data_dirs="$desired_dir"
          else
            prefix_data_dirs="$prefix_data_dirs:$desired_dir"
          fi
          ;;
      esac
    done
    if [ -n "$prefix_data_dirs" ]; then
      if [ -n "$XDG_DATA_DIRS" ]; then
        export XDG_DATA_DIRS="$prefix_data_dirs:$XDG_DATA_DIRS"
      else
        export XDG_DATA_DIRS="$prefix_data_dirs"
      fi
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

in
with pkgs; [
  # Custom wrapped Hyprland with GBM path fix (provides both hyprland and Hyprland)
  hyprland-both-cases

  # Hyprctl (Hyprland control CLI)
  hyprctl-wrapped

  # Hyprland Start Binary
  start-hyprland-wrapped

  # Hyprlock with nixGL wrapper
  (homeLib.gfx hyprlock)

  # Hyprland GUI utilities (from flake input)
  (homeLib.gfxExe "hyprland-guiutils" guiutils)

  # Hyprland ecosystem
  (homeLib.gfx hyprshot)
  hyprlang
  hyprkeys
  hypridle
  (homeLib.gfx hyprpaper)
  hyprsunset
  (homeLib.gfx hyprpicker)
  hyprcursor
  hyprpolkitagent
  hyprutils
  hyprprop
  (homeLib.gfx hyprsysteminfo)
  hyprwayland-scanner

  # Wayland tools
  wlprop
  wayland-scanner
  wayland-utils
  (homeLib.gfx xwayland)
  (homeLib.gfx slurp) # Screen area selection tool for screensharing picker
  (homeLib.gfx grim) # Screenshot utility (works with slurp)

  # Desktop components (GUI apps need wrapping)
  (homeLib.gfx waybar)
  (homeLib.gfx ashell)
  swaync-wrapped # Custom wrapper with Wayland display auto-detection
  (homeLib.gfx rofi)
  (homeLib.gfx bemenu)

  # Portals
  hyprwire
  hyprland-protocols
  xdg-desktop-portal
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-wlr

  # Clipboard
  wl-clip-persist
]
