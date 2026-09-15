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
        sd
        eza
        bat
        fzf
        ripgrep
        ast-grep
        zoxide
        difftastic
        just

        curl
        wget
        tokei

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

        hyprfine
        tabiew
        nushell
        gum
        goaccess
      ];
    };
}
