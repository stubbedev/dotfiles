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

  # Theme names referenced across modules. Keep in lockstep with what
  # modules/theme/gtk.nix actually selects.
  theme = {
    icon = "Tela-circle-purple-dark";
    cursor = "Vimix-cursors";
    cursorSize = 24;
    gtk = "catppuccin-mocha-mauve-standard";
    kvantum = "Catppuccin-Mocha-Mauve";
    sddm = "catppuccin-mocha-mauve";
    plymouth = "catppuccin-mocha";
  };
}
