_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    {
      config,
      pkgs,
      ...
    }:
    {
      actionScript = ''
        rm -f "${config.home.homeDirectory}/.zcompdump" "${config.home.homeDirectory}/.zcompdump.zwc"
        ${pkgs.zsh}/bin/zsh <<'ZSHEOF'
        export HOME='${config.home.homeDirectory}'
        STBDIR='${config.home.homeDirectory}/.stubbe/src/zsh'

        fpath=(
          '${config.home.homeDirectory}/.stubbe/src/zsh/fpaths.default.d'
          '${config.home.homeDirectory}/.stubbe/src/zsh/fpaths.d'
          '${config.home.homeDirectory}/.nix-profile/share/zsh/site-functions'
          $fpath
        )

        [ -f "$STBDIR/paths" ] && source "$STBDIR/paths"
        [ -f "$STBDIR/apaths" ] && source "$STBDIR/apaths"
        [ -f "$STBDIR/sysfuncs" ] && source "$STBDIR/sysfuncs"
        [ -f "$STBDIR/manager" ] && source "$STBDIR/manager"
        [ -f "$STBDIR/funcs" ] && source "$STBDIR/funcs"

        autoload -Uz compinit
        compinit -d '${config.home.homeDirectory}/.zcompdump'

        # Append dynamic autoload + compdef registrations that can't be captured by #compdef directives
        {
          print -r -- "autoload -Uz _git_shortcuts"
          print -r -- "compdef _git_shortcuts ''${(k)_git_shorthand_docs}"
        } >> '${config.home.homeDirectory}/.zcompdump'

        zcompile '${config.home.homeDirectory}/.zcompdump'

        # Compile plugin files for faster startup
        for plugin_file in "$STBDIR/plugins.d"/**/*.plugin.zsh(N); do
          zcompile "$plugin_file" 2>/dev/null
        done
        ZSHEOF
      '';
    };
}
