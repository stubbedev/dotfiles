{ pkgs, config }:

with pkgs;[
  dbeaver-bin
  ghostty
  (config.lib.nixGL.wrap alacritty)
  (config.lib.nixGL.wrap mailspring)
]
