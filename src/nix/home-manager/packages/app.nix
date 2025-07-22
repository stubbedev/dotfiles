{ pkgs, config, ... }:
with pkgs; [
  (config.lib.nixGL.wrap ghostty)
  (config.lib.nixGL.wrap mongodb-compass)
  (config.lib.nixGL.wrap alacritty)
  (config.lib.nixGL.wrap mailspring)
  (config.lib.nixGL.wrap dbeaver-bin)
]
