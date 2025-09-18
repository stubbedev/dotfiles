{ pkgs, config, ... }:
with pkgs; [
  (config.lib.nixGL.wrap mongodb-compass)
  (config.lib.nixGL.wrap alacritty)
  (config.lib.nixGL.wrap ghostty)
]

