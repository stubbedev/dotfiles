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

  # Clipboard managers
  clipman
  cliphist
]
