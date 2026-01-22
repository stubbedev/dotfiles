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
    term = "${config.home.homeDirectory}/.nix-profile/bin/alacritty";

    # Target paths
    tmuxPlugins = "${config.home.homeDirectory}/.tmux/plugins";
    lazygitConfig = "${config.home.homeDirectory}/.config/lazygit";

    customBinLock = "${config.home.homeDirectory}/.local/post-install.lock";
    customBinDir = "${config.home.homeDirectory}/.local/bin";
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

