# The baseline CLI: what every interactive shell on any host is expected to
# have. Deliberately NOT gated on features.desktop — a headless box without
# git or tmux is unusable.
_: {
  flake.modules.homeManager.cli =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # Shell and terminal
        bc
        zsh
        zsh-completions
        zsh-patina
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

        # Network
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

        # Nix static analysis
        statix

        # Version control
        git
        lazygit
        lazydocker
        gh

        # Archives
        zip
        unzip
        p7zip
        rar # ships both rar and unrar

        # Misc system
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

        # TUI odds and ends
        tabiew
        nushell
        glow
        gum
        goaccess
      ];
    };
}
