_: {
  flake.modules.nixos.shell =
    {
      config,
      pkgs,
      ...
    }:
    {
      # System-wide zsh: registers /run/current-system/sw/bin/zsh in
      # /etc/shells, sets up bash-like completion bridges, and makes zsh
      # a valid login shell. Without this, chsh and login both reject
      # zsh as the user's shell.
      programs.zsh.enable = true;

      # Make the primary user's login shell zsh so greetd / tty login
      # drop straight into it. The HM-side modules/files/shell.nix
      # writes ~/.zshrc that sources ${HOME}/.stubbe/src/zsh/init, so
      # the symlink created by bin/stb-install-nixos must exist for the
      # config to load.
      users.users.${config.host.primaryUser}.shell = pkgs.zsh;

      environment.shells = [ pkgs.zsh ];
    };
}
