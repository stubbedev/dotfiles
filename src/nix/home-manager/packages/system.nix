# System services and utilities
{ pkgs, homeLib, systemInfo, ... }:
let
  alacritty-wrapped = homeLib.gfx pkgs.alacritty;
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

  util-linux
]
