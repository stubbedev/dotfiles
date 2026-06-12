_: {
  flake.modules.nixos.shell =
    {
      config,
      pkgs,
      ...
    }:
    {
      programs.zsh = {
        # System-wide zsh: registers /run/current-system/sw/bin/zsh in
        # /etc/shells, sets up bash-like completion bridges, and makes zsh
        # a valid login shell. Without this, chsh and login both reject
        # zsh as the user's shell.
        enable = true;
        # NixOS defaults to enableGlobalCompInit=true and enableBashCompletion=true,
        # which inject `autoload -U compinit && compinit` into /etc/zshrc. That fires
        # before ~/.zshrc with no -C flag and re-audits /nix/store fpath dirs whose
        # mtimes change on every rebuild, invalidating ~/.zcompdump and defeating
        # the zcompile work done by modules/activation/_non-privileged/setup-zsh.nix.
        # Our init runs its own `compinit -C` against the precompiled dump.
        enableGlobalCompInit = false;
        enableBashCompletion = false;
      };

      # Make the primary user's login shell zsh so greetd / tty login
      # drop straight into it. The HM-side modules/files/shell.nix
      # writes ~/.zshrc that sources ${HOME}/.stubbe/src/zsh/init, so
      # the symlink created by bin/stb-install-nixos must exist for the
      # config to load.
      users.users.${config.host.primaryUser}.shell = pkgs.zsh;

      environment.shells = [ pkgs.zsh ];
    };
}
