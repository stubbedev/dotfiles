{ pkgs, config, ... }:

with pkgs; [
  networkmanagerapplet
  networkmanager-openconnect
  blueman
  clipman
  cliphist
  globalprotect-openconnect
]
