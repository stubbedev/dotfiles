# System services and utilities
{ pkgs, ... }:
with pkgs; [
  # Network management
  networkmanager
  networkmanagerapplet
  networkmanager-openconnect
  globalprotect-openconnect

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
