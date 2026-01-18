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

  # Create hyprctl wrapper with automatic instance signature detection
  hyprctl-wrapped = pkgs.writeShellScriptBin "hyprctl" ''
    # Auto-detect Hyprland instance signature if not set
    if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
      export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/$(id -u)/hypr/ 2>/dev/null | grep -v "unknown" | head -1)
    fi

    # Call hyprctl
    exec ${hyprlandPkg}/bin/hyprctl "$@"
  '';

in with pkgs; [
  # Custom wrapped Hyprland with GBM path fix
  hyprland-wrapped

  # Hyprctl (Hyprland control CLI)
  hyprctl-wrapped

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

  # Desktop components (GUI apps need wrapping)
  (wrap waybar)
  (wrap ashell)
  (wrap swaynotificationcenter)
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
