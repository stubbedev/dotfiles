# System services and utilities
{ pkgs, config, ... }:
let
  wrap = config.lib.nixGL.wrap;
in
with pkgs; [
  # Terminal emulator (GPU accelerated)
  (wrap alacritty)

  # Network management (GUI applets)
  (wrap networkmanagerapplet)
  networkmanager-openconnect

  # Bluetooth (GUI)
  (wrap blueman)

  # Monitor Brightness (CLI tools)
  brightnessctl
  ddcutil

  # Clipboard managers (CLI/daemon)
  clipman
  cliphist

  # Mail (TUI, no GPU needed)
  mailutils
  aerc
]
