{ config, ... }:

{
  # Path constants
  paths = {
    dotfiles = "${config.home.homeDirectory}/.stubbe";
    configSrc = "${config.home.homeDirectory}/.stubbe/src";

    # Individual config paths
    zsh = "${config.home.homeDirectory}/.stubbe/src/zsh";
    nvim = "${config.home.homeDirectory}/.stubbe/src/nvim";
    hypr = "${config.home.homeDirectory}/.stubbe/src/hypr";

    # Target paths
    tmuxPlugins = "${config.home.homeDirectory}/.tmux/plugins";
    lazygitConfig = "${config.home.homeDirectory}/.config/lazygit";
  };

  # User information
  user = {
    name = "stubbe";
    fullName = "Alexander Bugge Stage";
    email = "abs@stubbe.dev";
  };

  # Theme configuration
  theme = {
    iconTheme = "stubbe";
    gtkTheme = "stubbe";
  };
}

