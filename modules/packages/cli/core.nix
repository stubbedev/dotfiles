# Core CLI utilities and build tools. Unconditional — these are the
# baseline tooling we expect on every interactive shell (headless or
# not). Don't gate on features.desktop: a headless host without `git`
# or `tmux` would be unusable.
_: {
  flake.modules.homeManager.packagesCliCore =
    {
      pkgs,
      ...
    }:
    {
      home.packages = with pkgs; [
        # Shell and terminal
        bc
        zsh
        zsh-completions
        tmux
        starship

        # Modern CLI replacements
        fd
        eza
        bat
        fzf
        ripgrep
        zoxide
        just

        # System monitoring
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

        # Nix linter
        statix

        # Version control
        git
        lazygit
        lazydocker
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
      ];
    };
}
