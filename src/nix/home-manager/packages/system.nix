{ pkgs, config, ... }:

with pkgs; [
  networkmanager
  networkmanagerapplet
  networkmanager-openconnect
  blueman
  clipman
  cliphist
  globalprotect-openconnect
]
