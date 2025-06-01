{ config, pkgs, nixGL, ... }:
{
  programs.alacritty = {
    enable = true;
    package = nixGL.nixGLDefault pkgs.alacritty;
  };
}
