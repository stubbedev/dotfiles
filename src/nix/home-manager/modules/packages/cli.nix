# Core CLI utilities and build tools
{ ... }:
{
  flake.modules.homeManager.packages.cli = { pkgs, ... }: {
    home.packages = with pkgs; [
      # Shell and terminal
      bc
      zsh
      tmux
      starship

      # Modern CLI replacements
      fd
      eza
      bat
      fzf
      ripgrep
      tree-sitter
      zoxide
      just

      # System monitoring
      htop
      btop

      # Network utilities
      curl
      wget

      # Data processing
      jq
      yq
      jless

      # Text processing
      gnugrep
      hunspell
      gawk

      # Python runtime for scripts
      python315

      # Nix linter
      statix

      # Version control
      git
      lazygit
      gh

      # Archive handling
      zip
      unzip
      p7zip

      # System utilities
      xsel
      less
      more

      # Build essentials
      gcc
      gnumake
      gnutar
      coreutils
      cmake
      pkg-config
      gettext
      libtool
      autoconf
      automake

      # Terminal file manager
      tabiew
      nushell
      glow
      gum
      goaccess

      # Mailing
      msmtp
      w3m
      pandoc
      elinks
      lynx
      chafa
      catimg
    ];
  };
}
