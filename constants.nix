{ config, ... }:
{
  paths = {
    dotfiles = "${config.home.homeDirectory}/.stubbe";
    zsh = "${config.home.homeDirectory}/.stubbe/src/zsh";
    nixBin = "${config.home.homeDirectory}/.nix-profile/bin";
    term = "${config.home.homeDirectory}/.nix-profile/bin/alacritty";
  };

  theme = {
    iconTheme = "stubbe";
    gtkTheme = "stubbe";
  };
}
