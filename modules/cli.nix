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

          fd
          sd
          eza
          bat
          fzf
          ripgrep
          zoxide

          curl
          wget
          rsync
          tree

          jq
          yq

          gnugrep
          gawk

          zip
          unzip
          p7zip

          less
          more

          gnutar
          coreutils
          gettext
        ]
        ++ lib.optionals config.features.development [
          ast-grep
          difftastic
          just
          tokei
          jless
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
