_: {
  enableIf = { config, ... }: config.features.desktop;
  # Must run AFTER setup-shell-completions writes _gh / _uv / _frankenphp /
  # ... into fpaths.d, otherwise compinit caches a zcompdump that doesn't
  # know about them and the user has to manually `rm ~/.zcompdump*` after
  # every switch.
  after = [ "non-privileged-setup-shell-completions" ];
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

        # Use the same fpath construction the interactive shell does so the
        # zcompdump matches the runtime fpath exactly.
        source "$STBDIR/fpaths"

        [ -f "$STBDIR/paths" ] && source "$STBDIR/paths"
        [ -f "$STBDIR/apaths" ] && source "$STBDIR/apaths"
        [ -f "$STBDIR/sysfuncs" ] && source "$STBDIR/sysfuncs"
        [ -f "$STBDIR/manager" ] && source "$STBDIR/manager"
        [ -f "$STBDIR/funcs" ] && source "$STBDIR/funcs"

        autoload -Uz compinit
        compinit -d '${config.home.homeDirectory}/.zcompdump'

        # Append dynamic autoload + compdef registrations that #compdef
        # directives can't capture. compinit's dump is plain zsh source; the
        # appended lines run when init's `compinit -C` re-evals the dump on
        # next shell start. One file, one source — keeps startup paths short.
        {
          print -r -- "autoload -Uz _git_shortcuts"
          print -r -- "compdef _git_shortcuts ''${(k)_git_shorthand_docs}"
        } >>'${config.home.homeDirectory}/.zcompdump'

        zcompile '${config.home.homeDirectory}/.zcompdump'

        # Compile plugin files for faster startup
        for plugin_file in "$STBDIR/plugins.d"/**/*.plugin.zsh(N); do
          zcompile "$plugin_file" 2>/dev/null
        done

        # Compile source files for faster parsing on startup
        for src_file in init paths fpaths apaths sysfuncs manager funcs aliases settings env; do
          [[ -f "$STBDIR/$src_file" ]] && zcompile "$STBDIR/$src_file" 2>/dev/null
        done
        ZSHEOF
      '';
    };
}
