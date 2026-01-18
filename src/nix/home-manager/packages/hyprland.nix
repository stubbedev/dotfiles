# Hyprland compositor and related tools
{ pkgs, config, hyprland, hyprland-guiutils, hy3, systemInfo, ... }:
let
  inherit (config.lib.nixGL) wrap;
  guiutils = hyprland-guiutils.packages.${pkgs.system}.default;
  hyprlandPkg = hyprland.packages.${pkgs.system}.hyprland;

  # Create custom Hyprland wrapper with GBM backend path fix for non-NixOS
  # This is needed because Nix's mesa-libgbm doesn't include GBM backends
  hyprland-wrapped = pkgs.writeShellScriptBin "hyprland" ''
    # Set GBM/DRI paths to use system libraries (needed on non-NixOS)
    # Auto-detected: ${
      if systemInfo.isFedora then "Fedora (lib64)" else "Generic Linux (lib)"
    }
    export GBM_BACKENDS_PATH=/usr/${systemInfo.libPath}/gbm:/usr/lib/gbm
    export LIBGL_DRIVERS_PATH=/usr/${systemInfo.libPath}/dri:/usr/lib/dri

    # Call the nixGL-wrapped Hyprland from official flake
    exec ${wrap hyprlandPkg}/bin/hyprland "$@"
  '';

  # Create hyprctl wrapper (doesn't need GPU wrapping, it's just a control CLI)
  hyprctl-wrapped = pkgs.writeShellScriptBin "hyprctl" ''
    # hyprctl doesn't need GPU wrapping, call it directly
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
