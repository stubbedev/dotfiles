{ config, ... }:
{
  paths = {
    dotfiles = "${config.home.homeDirectory}/.stubbe";
    zsh = "${config.home.homeDirectory}/.stubbe/src/zsh";
    # home.profileDirectory resolves to /etc/profiles/per-user/$USER under
    # NixOS (useUserPackages) and ~/.nix-profile under standalone HM.
    nixBin = "${config.home.profileDirectory}/bin";
    term = "${config.home.profileDirectory}/bin/alacritty";
  };

  theme = {
    iconTheme = "stubbe";
    gtkTheme = "stubbe";
  };
}
