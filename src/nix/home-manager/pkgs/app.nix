{ pkgs, config }:

[
  pkgs.dbeaver-bin
  pkgs.ghostty
  (config.lib.nixGL.wrap pkgs.alacritty)
]
