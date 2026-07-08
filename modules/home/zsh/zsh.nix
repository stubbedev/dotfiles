# Fully Nix-managed zsh: programs.zsh owns .zshrc/.zshenv, all config
# files/plugins/completions/init scripts/zcompdump are store paths built
# and zcompiled at nix build time (./_packages.nix). Load-order contract
# (pre-files → compinit → aliases → plugins → settings → generated inits
# → patina) is preserved via mkOrder slots: pre=500 < completionInit=550
# < post=1000.
_: {
  flake.modules.homeManager.zsh =
    {
      config,
      lib,
      pkgs,
      self,
      srv,
      treeman,
      zsh-vim-mode,
      zsh-fzf-artisan,
      zsh-fzf-npm-run,
      ...
    }:
    let
      # Args are named in the pattern because the module system only
      # injects _module.args entries NAMED there; the inherit forwards
      # exactly what _packages.nix declares.
      z = import ./_packages.nix {
        inherit
          config
          lib
          pkgs
          self
          srv
          treeman
          zsh-vim-mode
          zsh-fzf-artisan
          zsh-fzf-npm-run
          ;
      };
      sourcePlugins = lib.concatMapStringsSep "\n" (
        p: "source ${z.zshPlugins}/${p.name}/${p.file}"
      ) z.pluginSpecs;
    in
    lib.mkIf config.features.desktop {
      programs.zsh = {
        enable = true;
        enableCompletion = true;
        # Read-only store dump; never audits, never rewrites. The adjacent
        # .zwc is what actually gets sourced (equal store mtimes ⇒ zwc wins).
        completionInit = ''
          autoload -Uz compinit
          compinit -C -d ${z.zcompdump}/zcompdump
        '';
        # Ubuntu's /etc/zsh/zshrc runs compinit with the system-default
        # fpath; sourced from .zshenv (before /etc/zshrc) this suppresses
        # that global compinit so ours is the only one.
        envExtra = "skip_global_compinit=1";
        history = {
          path = "${config.home.homeDirectory}/.zsh_history";
          size = 10000;
          save = 10000;
          extended = true;
          share = true;
          append = true;
          ignoreAllDups = true;
        };
        initContent = lib.mkMerge [
          # Pre-compinit: helpers + fpath. Same fpath list the zcompdump
          # derivation was built against — pinned by construction.
          (lib.mkOrder 500 ''
            source ${z.zshConfig}/paths
            source ${z.zshConfig}/apaths
            source ${z.zshConfig}/sysfuncs
            source ${z.zshConfig}/funcs
            ${z.fpathLine}
          '')
          # Post-compinit: fzf-tab must load right after compinit; patina
          # last so its ZLE hooks wrap the final widget set. Its init
          # script is generated at switch time by the setup-zsh-patina
          # activation (activate is impure — daemon side effects).
          (lib.mkOrder 1000 ''
            source ${z.zshConfig}/aliases
            ${sourcePlugins}
            source ${z.zshConfig}/settings
            (( $+commands[fzf] ))      && source ${z.fzfInit}
            (( $+commands[starship] )) && source ${z.starshipInit}
            (( $+commands[zoxide] ))   && source ${z.zoxideInit}
            (( $+commands[direnv] ))   && source ${z.direnvInit}
            _patina_init="${config.xdg.cacheHome}/zsh/patina-init.zsh"
            [[ -f "$_patina_init" ]] && source "$_patina_init"
            unset _patina_init
          '')
        ];
      };
    };
}
