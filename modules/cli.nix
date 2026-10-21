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
        rsync
        tree
        tokei

        jq
        yq
        jless

        gnugrep
        gawk

        lazydocker
        gh

        zip
        unzip
        p7zip
        rar

        xsel
        xclip
        less
        more

        gnutar
        coreutils
        gettext

        hyperfine
      ];
    };
}
