# zsh, fully Nix-managed.
#
# Everything the shell reads at startup is a store path built and zcompiled at
# Nix build time: config files, plugins, generated completions, the
# tool-init scripts, and the compinit dump. Nothing is cloned, cached or
# compiled at runtime, and there is no writable ~/.zcompdump.
#
# zwc semantics this relies on: zsh ignores a .zwc only when the source is
# STRICTLY newer, and store mtimes are all epoch-equal — so the adjacent .zwc
# always wins, for both `source` and autoload.
#
# Load-order contract (pre-files → compinit → aliases → plugins → settings →
# generated inits → patina) is held by mkOrder slots: pre=500 <
# completionInit=550 < post=1000.
{ inputs, ... }:
{
  flake.modules.nixos.shell =
    { config, pkgs, ... }:
    {
      programs.zsh = {
        # System-wide zsh registers /run/current-system/sw/bin/zsh in
        # /etc/shells, sets up the bash-completion bridges, and makes zsh a
        # valid login shell. Without it, chsh and login both reject zsh.
        enable = true;
        # NixOS defaults both of these on, which injects `autoload -U compinit
        # && compinit` into /etc/zshrc. That fires before ~/.zshrc with no -C
        # flag and re-audits store fpath dirs whose mtimes change on every
        # rebuild. The HM half runs its own `compinit -C` against a prebuilt
        # store dump, so the global one is pure waste.
        enableGlobalCompInit = false;
        enableBashCompletion = false;
      };

      # Login shell for the primary user, so greetd and tty login drop straight
      # into it. .zshrc is owned by the HM half and sources only store paths,
      # so shell startup does not depend on the ~/.stubbe checkout existing.
      users.users.${config.host.primaryUser}.shell = pkgs.zsh;
      environment.shells = [ pkgs.zsh ];
    };

  flake.modules.homeManager.shell =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      system = pkgs.stdenv.hostPlatform.system;

      # Content-addressed copy of just src/shell/zsh, so these derivations
      # rebuild only when a zsh source file changes — not on every flake input
      # or unrelated repo edit. The flake source is already git-filtered, so
      # gitignored legacy junk (plugins.d, fpaths.d, *.zwc) never lands here.
      zshSrc = pkgs.stubbe.file "src/shell/zsh";

      # Tracked src/shell/zsh files, zcompiled.
      zshConfig = pkgs.runCommandLocal "stubbe-zsh-config" { nativeBuildInputs = [ pkgs.zsh ]; } ''
        mkdir -p $out
        cp -r ${zshSrc}/. $out/
        chmod -R u+w $out
        # zcompile is a zsh builtin, so run it inside zsh.
        zsh -c 'for f in paths apaths sysfuncs funcs aliases settings; do zcompile $out/$f; done'
      '';

      # Source order matters and is preserved here.
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
          src = inputs.zsh-fzf-artisan;
          file = "artisan.plugin.zsh";
        }
        {
          name = "zsh-fzf-npm-run";
          src = inputs.zsh-fzf-npm-run;
          file = "zsh-fzf-npm-run.plugin.zsh";
        }
        {
          name = "zsh-vim-mode";
          src = inputs.zsh-vim-mode;
          file = "zsh-vim-mode.plugin.zsh";
        }
      ];

      # Whole plugin dirs (fzf-tab lazy-sources its lib/*.zsh relative to the
      # plugin file), entry files zcompiled.
      zshPlugins = pkgs.runCommandLocal "stubbe-zsh-plugins" { nativeBuildInputs = [ pkgs.zsh ]; } (
        lib.concatMapStrings (p: ''
          mkdir -p $out/${p.name}
          cp -rT ${p.src} $out/${p.name}
          chmod -R u+w $out/${p.name}
          zsh -c 'zcompile $out/${p.name}/${p.file}'
        '') pluginSpecs
      );

      # Only tools whose packages do NOT ship a zsh completion. Everything else
      # (_gh, _uv, _kubectl, _minikube, _vultr-cli, …) arrives via
      # ${config.home.path}/share/zsh/site-functions in the fpath below.
      zshCompletions = pkgs.runCommandLocal "stubbe-zsh-completions" { } ''
        dir=$out/share/zsh/site-functions
        mkdir -p $dir
        ${lib.getExe pkgs.lazygit} completion zsh > $dir/_lazygit
        ${lib.optionalString config.features.srv ''
          ${inputs.srv.packages.${system}.srv}/bin/srv completion zsh > $dir/_srv
        ''}
        ${lib.optionalString config.features.treeman ''
          ${inputs.treeman.packages.${system}.treeman}/bin/treeman completion zsh > $dir/_treeman
        ''}
        ${lib.optionalString config.features.wayle ''
          ${pkgs.wayle}/bin/wayle completions zsh > $dir/_wayle
        ''}
        ${lib.optionalString config.features.docker ''
          # The host docker CLI is not in the closure; pkgs.docker's completion
          # is protocol-stable across the minor version skew. Build-time-only
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
      # interpolated into both the .zshrc and the zcompdump builder.
      # config.home.path (the HM profile derivation) carries every
      # package-shipped completion on both targets, and forces a dump rebuild
      # whenever packages change.
      fpathLine = "fpath=(${
        lib.concatStringsSep " " [
          "${zshConfig}/completions"
          "${zshCompletions}/share/zsh/site-functions"
          "${config.home.path}/share/zsh/site-functions"
        ]
      } $fpath)";

      # Generator-init scripts, zcompiled. The derivation output is a directory
      # (zcompile writes the .zwc next to init.zsh, which must stay inside
      # $out); this returns the sourceable file so call sites need no suffix.
      mkInit =
        name: script:
        "${
          pkgs.runCommandLocal "zsh-${name}-init" { nativeBuildInputs = [ pkgs.zsh ]; } ''
            mkdir -p $out
            ${script}
            zsh -c 'zcompile $out/init.zsh'
          ''
        }/init.zsh";

      # Strip fzf's `bindkey '^I'` (Tab) so fzf-tab keeps Tab, and its Alt-C
      # bindkeys (the unused cd widget). The `zle -N fzf-cd-widget` line stays
      # so the `if` block fzf wraps them in is not left empty.
      fzfInit = mkInit "fzf" ''
        ${lib.getExe pkgs.fzf} --zsh \
          | grep -Fv "bindkey '^I'" \
          | grep -v 'bindkey.*fzf-cd-widget' > $out/init.zsh
      '';

      starshipInit = mkInit "starship" ''
        HOME=$TMPDIR ${lib.getExe pkgs.starship} init zsh --print-full-init > $out/init.zsh
      '';

      zoxideInit = mkInit "zoxide" ''
        ${lib.getExe pkgs.zoxide} init zsh > $out/init.zsh
      '';

      # A plain zsh hook; the "loading/export" chatter is silenced by direnv's
      # own log_filter (modules/development.nix), not a shell-side wrapper.
      direnvInit = mkInit "direnv" ''
        ${lib.getExe pkgs.direnv} hook zsh > $out/init.zsh
      '';

      # compinit dump built against the pinned fpath, with the dynamic
      # _git_shortcuts registrations appended. Runtime does `compinit -C -d
      # <this>` — read-only, no ~/.zcompdump ever again. -u because the sandbox
      # build user fails compaudit's ownership check, which is irrelevant at
      # runtime.
      zcompdump = pkgs.runCommandLocal "stubbe-zcompdump" { nativeBuildInputs = [ pkgs.zsh ]; } ''
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

      sourcePlugins = lib.concatMapStringsSep "\n" (
        p: "source ${zshPlugins}/${p.name}/${p.file}"
      ) pluginSpecs;
    in
    lib.mkIf config.features.desktop {
      programs.zsh = {
        enable = true;
        enableCompletion = true;
        # Read-only store dump; never audits, never rewrites. The adjacent .zwc
        # is what actually gets sourced (equal store mtimes ⇒ zwc wins).
        completionInit = ''
          autoload -Uz compinit
          compinit -C -d ${zcompdump}/zcompdump
        '';
        # Ubuntu's /etc/zsh/zshrc runs compinit with the system-default fpath;
        # sourced from .zshenv (before /etc/zshrc) this suppresses that global
        # compinit so ours is the only one.
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
          # Pre-compinit: helpers + fpath. The same fpath list the zcompdump
          # derivation was built against — pinned by construction.
          (lib.mkOrder 500 ''
            source ${zshConfig}/paths
            source ${zshConfig}/apaths
            source ${zshConfig}/sysfuncs
            source ${zshConfig}/funcs
            ${fpathLine}
          '')
          # Post-compinit: fzf-tab must load right after compinit; patina last
          # so its ZLE hooks wrap the final widget set. patina's init script is
          # generated at switch time by the activation below, because
          # `zsh-patina activate` is impure (daemon side effects).
          (lib.mkOrder 1000 ''
            source ${zshConfig}/aliases
            ${sourcePlugins}
            source ${zshConfig}/settings
            (( $+commands[fzf] ))      && source ${fzfInit}
            (( $+commands[starship] )) && source ${starshipInit}
            (( $+commands[zoxide] ))   && source ${zoxideInit}
            (( $+commands[direnv] ))   && source ${direnvInit}
            _patina_init="${config.xdg.cacheHome}/zsh/patina-init.zsh"
            [[ -f "$_patina_init" ]] && source "$_patina_init"
            unset _patina_init
          '')
        ];
      };

      home.file = {
        ".ideavimrc".source = pkgs.stubbe.file "src/dev/ideavimrc";
        ".prettierrc.json".source = pkgs.stubbe.file "src/dev/prettierrc.json";
      };

      # zsh-patina: the syntax-highlighting daemon that replaced
      # fast-syntax-highlighting. Two halves that must stay version-synced:
      #
      #   * the shell-side hook script, generated at switch time below because
      #     `zsh-patina activate` embeds $XDG_RUNTIME_DIR and starts the daemon,
      #     so it cannot be a build product; and
      #   * the daemon itself, owned by this service — the generated script
      #     never starts it, so without the unit highlighting would silently do
      #     nothing after a reboot.
      #
      # Both regenerate from the same binary on switch, so they cannot drift.
      systemd.user.services.zsh-patina = {
        Unit.Description = "zsh-patina syntax highlighting daemon";
        Service = {
          ExecStart = "${lib.getExe pkgs.zsh-patina} start --no-daemon";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "default.target" ];
      };

      stubbe.setup.zshPatina.script = ''
        # activate embeds $XDG_RUNTIME_DIR/zsh-patina as the socket path, and
        # NixOS runs user activation without XDG_RUNTIME_DIR — fall back to the
        # same path login shells get.
        export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        _patina_cache='${config.xdg.cacheHome}/zsh'
        mkdir -p "$_patina_cache"
        if ${lib.getExe pkgs.zsh-patina} activate > "$_patina_cache/patina-init.zsh.tmp" 2>/dev/null; then
          mv "$_patina_cache/patina-init.zsh.tmp" "$_patina_cache/patina-init.zsh"
          ${lib.getExe pkgs.zsh} -c 'zcompile "$1"' _ "$_patina_cache/patina-init.zsh" || true
        else
          # Keep a previous good script if activate fails (e.g. no runtime dir
          # in a container build); shells degrade to no highlighting.
          rm -f "$_patina_cache/patina-init.zsh.tmp"
        fi
        unset _patina_cache
      '';

      # Keep the avahi-discovered .local host cache warm for ssh-style
      # completion. avahi-browse takes ~1.5s, so the shell never runs it —
      # _avahi_ssh_hosts in src/shell/zsh/settings only reads this cache. The
      # service-type filter excludes Sonos boxes, printers and the like, so
      # only ssh-able machines show up.
      systemd.user = {
        services.zsh-avahi-hosts = {
          Unit.Description = "Refresh avahi .local host cache for zsh completion";
          Service = {
            Type = "oneshot";
            ExecStart =
              let
                cacheFile = "${config.xdg.cacheHome}/zsh-avahi-hosts";
              in
              pkgs.writeShellScript "zsh-avahi-hosts-refresh" ''
                set -u
                mkdir -p "$(dirname '${cacheFile}')"
                tmp='${cacheFile}.tmp'
                # avahi-browse talks to the system avahi-daemon over D-Bus; if
                # the host runs no daemon this fails and we keep the old cache.
                if ${pkgs.avahi}/bin/avahi-browse -atrp 2>/dev/null \
                     | ${lib.getExe pkgs.gawk} -F';' '$1=="=" && $3=="IPv4" && ($5=="_workstation._tcp" || $5 ~ /ssh/) && $7!="" {print $7}' \
                     | sort -u > "$tmp" 2>/dev/null; then
                  mv "$tmp" '${cacheFile}'
                else
                  rm -f "$tmp"
                fi
              '';
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };

        timers.zsh-avahi-hosts = {
          Unit.Description = "Periodic avahi host cache refresh";
          Timer = {
            # The LAN host set is near-static, so a slow poll keeps the cache
            # fresh enough for completion without waking every minute.
            OnBootSec = "30s";
            OnUnitActiveSec = "10min";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
