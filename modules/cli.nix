_: {
  flake.modules.homeManager.cli =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      home.packages =
        with pkgs;
        [
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

          less
          more

          gnutar
          coreutils
          gettext

          hyperfine
        ]
        # rar is a closed-source x86 binary; the platforms it covers are in its
        # own metadata, so ask rather than list them twice.
        ++ lib.optionals (lib.meta.availableOn stdenv.hostPlatform rar) [ rar ]
        # X11 clipboard shims: nothing outside a desktop session has an X
        # display to talk to.
        ++ lib.optionals config.features.desktop [
          xsel
          xclip
        ];
    };
}
