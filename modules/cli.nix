_: {
  flake.modules.homeManager.cli =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        bc
        zsh
        zsh-completions
        zsh-patina
        tmux
        starship

        fd
        eza
        bat
        fzf
        ripgrep
        zoxide
        just

        curl
        wget

        jq
        yq
        jless

        gnugrep
        hunspell
        gawk

        statix

        git
        lazygit
        lazydocker
        gh

        zip
        unzip
        p7zip
        rar

        xsel
        less
        more

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

        tabiew
        nushell
        gum
        goaccess
      ];
    };
}
