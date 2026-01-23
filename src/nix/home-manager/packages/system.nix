# System services and utilities
{ pkgs, config, systemInfo, ... }:
let
  inherit (config.lib.nixGL) wrap;

  alacritty-wrapped = pkgs.writeShellScriptBin "alacritty" (''
    # GPU detected at build time: ${if systemInfo.hasNvidia then "NVIDIA" else "Intel/Mesa"}
    # Using wrapper: ${systemInfo.nixGLWrapper}
  '' + (if systemInfo.hasNvidia then ''
    # NVIDIA: Find the versioned binary (e.g., nixGLNvidia-560.35.03)
    NIXGL_BIN=$(ls ${systemInfo.nixGLWrapper}/bin/nixGLNvidia* 2>/dev/null | head -1)
    exec "$NIXGL_BIN" ${pkgs.alacritty}/bin/alacritty "$@"
  '' else ''
    # Intel/AMD: Use nixGLIntel directly
    exec ${systemInfo.nixGLWrapper}/bin/nixGLIntel ${pkgs.alacritty}/bin/alacritty "$@"
  ''));
in
with pkgs; [
  # Terminal emulator (GPU accelerated)
  alacritty-wrapped

  # Network management (GUI applets)
  networkmanagerapplet
  networkmanager-openconnect

  # Bluetooth (GUI)
  blueman

  # Monitor Brightness (CLI tools)
  brightnessctl
  ddcutil

  # Clipboard managers (CLI/daemon)
  clipman
  cliphist

  # Mail (TUI, no GPU needed)
  mailutils
  aerc

  # Keyring management (for automatic password management)
  # Note: Uses system-installed GNOME Keyring and KDE Wallet from Fedora
  libsecret  # Provides secret-tool command

  # Cursor and icon themes
  vimix-cursors
  vimix-icon-theme
]
