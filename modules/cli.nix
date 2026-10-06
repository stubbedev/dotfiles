_: {
  flake.modules.homeManager.cli =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        bc
        zsh-completions
        zsh-patina
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

        hyperfine
      ];
    };
}
