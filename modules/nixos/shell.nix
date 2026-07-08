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
        # mtimes change on every rebuild. Our HM-side programs.zsh runs its own
        # `compinit -C` against the prebuilt store dump (modules/home/zsh/), so the
        # global one is pure waste — disable it.
        enableGlobalCompInit = false;
        enableBashCompletion = false;
      };

      # Make the primary user's login shell zsh so greetd / tty login
      # drop straight into it. The .zshrc is owned by HM's programs.zsh
      # (modules/home/zsh/zsh.nix) and sources only /nix/store paths, so
      # zsh loading no longer depends on the ~/.stubbe symlink.
      users.users.${config.host.primaryUser}.shell = pkgs.zsh;

      environment.shells = [ pkgs.zsh ];
    };
}
