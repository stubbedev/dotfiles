{ config, pkgs, ... }:
{
  programs.alacritty = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.hyprland;
  };
}
