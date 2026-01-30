{ ... }:
let
  helpers = import ../_helpers.nix;
  order = import ../_order.nix;
in
helpers.mkSetupModule {
  moduleName = "activationApplyMutableConfigZsh";
  activationName = "applyMutableConfigZsh";
  after = order.after.mutableConfig;
  enableIf = { config, ... }: config.features.desktop;
  script = { config, pkgs, ... }: ''
    echo "Regenerating zsh completion cache..."
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
    ZSHEOF
  '';
}
