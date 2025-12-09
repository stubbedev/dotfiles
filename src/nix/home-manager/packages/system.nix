# System services and utilities
{ pkgs, ... }:
with pkgs; [
  # Network management (using system NetworkManager, only adding applet and plugin)
  networkmanagerapplet
  networkmanager-openconnect

  # Bluetooth
  blueman

  # Monitor Brightness
  brightnessctl
  ddcutil

  # Clipboard managers
  clipman
  cliphist

  mailutils
  aerc
]
