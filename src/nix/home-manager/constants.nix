{ config, ... }:
{
  # Path constants
  paths = {
    dotfiles = "${config.home.homeDirectory}/.stubbe";
    zsh = "${config.home.homeDirectory}/.stubbe/src/zsh";
    hypr = "${config.home.homeDirectory}/.stubbe/src/hypr";
    term = "${config.home.homeDirectory}/.nix-profile/bin/alacritty";
  };

  # User information
  user = {
    name = "stubbe";
  };

  # Theme configuration
  theme = {
    iconTheme = "stubbe";
    gtkTheme = "stubbe";
  };
}
