# All zsh build products: config files, plugins, generated completions,
# generator-init scripts, and the compinit dump — everything zcompiled at
# nix build time so shell startup never compiles or forks generators.
# Imported by ./zsh.nix (import-tree skips _-prefixed files, same
# convention as modules/activation/_helpers.nix).
#
# zwc semantics this relies on: zsh ignores a .zwc only when the source
# is *strictly newer*; nix store mtimes are all epoch-equal, so the
# adjacent .zwc always wins for both `source` and autoload.
{
  pkgs,
  lib,
  self,
  config,
  srv,
  treeman,
  zsh-vim-mode,
  zsh-fzf-artisan,
  zsh-fzf-npm-run,
}:
rec {
  # Content-addressed copy of just src/zsh, so these derivations rebuild
  # only when a zsh source file changes — not on every flake input or
  # unrelated repo edit (which `${self}/…` would drag in). The flake
  # source is already git-filtered, so gitignored legacy junk (plugins.d,
  # fpaths.d, *.zwc) never lands here.
  zshSrc = builtins.path {
    path = self + "/src/zsh";
    name = "stubbe-zsh-src";
  };

  # Tracked src/zsh files, zcompiled.
  zshConfig =
    pkgs.runCommandLocal "stubbe-zsh-config"
      {
        nativeBuildInputs = [ pkgs.zsh ];
      }
      ''
        mkdir -p $out
        cp -r ${zshSrc}/. $out/
        chmod -R u+w $out
        # zcompile is a zsh builtin, so run it inside zsh
        zsh -c 'for f in paths apaths sysfuncs funcs aliases settings; do zcompile $out/$f; done'
      '';

  # Source order preserved from the retired src/zsh/plugins list.
  pluginSpecs = [
    {
      name = "fzf-tab";
      src = "${pkgs.zsh-fzf-tab}/share/fzf-tab";
      file = "fzf-tab.plugin.zsh";
    }
    {
      name = "zsh-autosuggestions";
      src = "${pkgs.zsh-autosuggestions}/share/zsh/plugins/zsh-autosuggestions";
      file = "zsh-autosuggestions.zsh";
    }
    {
      name = "zsh-fzf-artisan";
      src = zsh-fzf-artisan;
      file = "artisan.plugin.zsh";
    }
    {
      name = "zsh-fzf-npm-run";
      src = zsh-fzf-npm-run;
      file = "zsh-fzf-npm-run.plugin.zsh";
    }
    {
      name = "zsh-vim-mode";
      src = zsh-vim-mode;
      file = "zsh-vim-mode.plugin.zsh";
    }
  ];

  # Whole plugin dirs (fzf-tab lazy-sources its lib/*.zsh relative to the
  # plugin file), entry files zcompiled.
  zshPlugins =
    pkgs.runCommandLocal "stubbe-zsh-plugins"
      {
        nativeBuildInputs = [ pkgs.zsh ];
      }
      (
        lib.concatMapStrings (p: ''
          mkdir -p $out/${p.name}
          cp -rT ${p.src} $out/${p.name}
          chmod -R u+w $out/${p.name}
          zsh -c 'zcompile $out/${p.name}/${p.file}'
        '') pluginSpecs
      );

  # Only tools whose nixpkgs/flake packages do NOT ship a zsh completion.
  # Everything else (_gh, _uv, _kubectl, _minikube, _vultr-cli, …) comes in
  # via ${config.home.path}/share/zsh/site-functions below.
  zshCompletionsGenerated =
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    pkgs.runCommandLocal "stubbe-zsh-completions" { } ''
      dir=$out/share/zsh/site-functions
      mkdir -p $dir
      ${pkgs.lazygit}/bin/lazygit completion zsh > $dir/_lazygit
      ${lib.optionalString config.features.srv ''
        ${srv.packages.${system}.srv}/bin/srv completion zsh > $dir/_srv
      ''}
      ${lib.optionalString config.features.treeman ''
        ${treeman.packages.${system}.treeman}/bin/treeman completion zsh > $dir/_treeman
      ''}
      ${lib.optionalString config.features.wayle ''
        ${pkgs.wayle}/bin/wayle completions zsh > $dir/_wayle
      ''}
      ${lib.optionalString config.features.docker ''
        # Host docker CLI isn't in the closure; pkgs.docker's completion is
        # protocol-stable across the minor version skew. Build-time-only
        # dep — only this file lands in the runtime closure.
        cp ${pkgs.docker}/share/zsh/site-functions/_docker $dir/_docker
      ''}
      ${lib.optionalString config.features.php ''
        # FrankenPHP emits a Caddy-derived completion (it embeds Caddy);
        # rename caddy → frankenphp so the directives register against the
        # actual binary name.
        ${pkgs.frankenphp}/bin/frankenphp completion zsh \
          | sed 's/caddy/frankenphp/g' > $dir/_frankenphp
      ''}
    '';

  # Runtime fpath == dump-build fpath by construction: this one list is
  # interpolated into both the .zshrc and the zcompdump builder. home.path
  # (the HM profile derivation) carries every package-shipped completion on
  # both targets and forces a dump rebuild whenever packages change.
  fpathDirs = [
    "${zshConfig}/completions"
    "${zshCompletionsGenerated}/share/zsh/site-functions"
    "${config.home.path}/share/zsh/site-functions"
  ];

  # The exact fpath assignment, shared verbatim by the runtime .zshrc and
  # the zcompdump builder — the whole point is that they stay identical.
  fpathLine = "fpath=(${lib.concatStringsSep " " fpathDirs} $fpath)";

  # Generator-init scripts, zcompiled. The derivation output is a dir
  # (zcompile writes the .zwc next to init.zsh, which must stay inside
  # $out); mkInit returns the sourceable file path so call sites don't
  # repeat the /init.zsh suffix.
  mkInit =
    name: script:
    "${
      pkgs.runCommandLocal "zsh-${name}-init"
        {
          nativeBuildInputs = [ pkgs.zsh ];
        }
        ''
          mkdir -p $out
          ${script}
          zsh -c 'zcompile $out/init.zsh'
        ''
    }/init.zsh";

  # Strip fzf's `bindkey '^I'` (Tab) line so fzf-tab keeps Tab, and its
  # Alt-C `bindkey`s (cd widget — unused). The `zle -N fzf-cd-widget` line
  # stays so the `if` block fzf wraps them in is not left empty.
  fzfInit = mkInit "fzf" ''
    ${pkgs.fzf}/bin/fzf --zsh \
      | grep -Fv "bindkey '^I'" \
      | grep -v 'bindkey.*fzf-cd-widget' > $out/init.zsh
  '';

  starshipInit = mkInit "starship" ''
    HOME=$TMPDIR ${pkgs.starship}/bin/starship init zsh --print-full-init > $out/init.zsh
  '';

  zoxideInit = mkInit "zoxide" ''
    ${pkgs.zoxide}/bin/zoxide init zsh > $out/init.zsh
  '';

  # Plain zsh hook; the "loading/export" chatter is silenced by direnv's
  # own log_filter (modules/programs/direnv.nix), not a shell-side wrapper.
  direnvInit = mkInit "direnv" ''
    ${pkgs.direnv}/bin/direnv hook zsh > $out/init.zsh
  '';

  # compinit dump built against the pinned fpath, with the dynamic
  # _git_shortcuts registrations appended (parity with the retired
  # setup-zsh.nix activation). Runtime does `compinit -C -d <this>` —
  # read-only, no ~/.zcompdump ever again. -u because the sandbox build
  # user fails compaudit's ownership check; irrelevant at runtime.
  zcompdump =
    pkgs.runCommandLocal "stubbe-zcompdump"
      {
        nativeBuildInputs = [ pkgs.zsh ];
      }
      ''
        mkdir -p $out
        export HOME=$TMPDIR
        zsh -f <<'ZSHEOF'
        ${fpathLine}
        source ${zshConfig}/sysfuncs
        source ${zshConfig}/funcs
        autoload -Uz compinit
        compinit -u -d "$out/zcompdump"
        {
          print -r -- "autoload -Uz _git_shortcuts"
          print -r -- "compdef _git_shortcuts ''${(k)_git_shorthand_docs}"
        } >> "$out/zcompdump"
        zcompile "$out/zcompdump"
        ZSHEOF
      '';
}
