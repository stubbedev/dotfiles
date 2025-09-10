# System services and network management
# System-level utilities for networking, bluetooth, and system management
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

