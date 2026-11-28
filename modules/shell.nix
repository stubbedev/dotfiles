# Relies on zsh ignoring a .zwc only when the source is STRICTLY newer: store
# mtimes are epoch-equal, so the adjacent .zwc always wins.
{ inputs, ... }:
{
  flake.modules.nixos.shell =
    { config, pkgs, ... }:
    {
      programs.zsh = {
        enable = true;
        # NixOS defaults inject an unflagged `compinit` into /etc/zshrc, which
        # re-audits store fpath dirs on every rebuild. The HM half already runs
        # `compinit -C` against a prebuilt dump.
        enableGlobalCompInit = false;
        enableBashCompletion = false;
      };

      users.users.${config.host.primaryUser}.shell = pkgs.zsh;
      environment.shells = [
        pkgs.zsh
        "/etc/profiles/per-user/${config.host.primaryUser}/bin/zsh"
      ];
    };

  flake.modules.homeManager.shell =
    {
      config,
      lib,
      pkgs,
      osConfig ? null,
      ...
    }:
    let
      onAndroid = config.host.platform == "android";
      inherit (config.stubbe) launchers;

      gitShorthandDocs = {
        gcm = "treeman git commit — auto ticket prefix; trailing \\ opens editor";
        gp = "treeman git push — warns on protected/diverged branches";
        gcb = "treeman git switch — checkout/create branch, worktree-aware (cd)";
        ga = "treeman git add — interactive stage picker";
        gsd = "treeman git diff — working-tree diff";
        gd = "treeman git diff --pick — three-dot diff vs a picked branch";
        gcd = "treeman git diff --pick --patch — export three-dot diff to a file";
        gst = "treeman git status — short status";
        gg = "treeman git pull — current branch (--all for all)";
        gf = "treeman git fetch (--all for all remotes)";
        gsa = "treeman git stash — stash all local changes";
        gcs = "treeman git stash clear — drop the entire stash stack";
        gw = "treeman git wipe — stash + drop local changes (--all clears stack)";
        ggo = "treeman git pull --pick — pull a selected origin branch";
        gl = "treeman git log — interactive log (cherry-pick/revert/copy)";
        gsp = "treeman git stash pop — pick a stash to pop";
        gwt = "treeman worktree switch — switch/create a branch worktree (cd; `-` toggles previous)";
        gwtd = "treeman worktree delete — remove a worktree (picker with no arg)";
        gwte = "treeman worktree back — cd to main repo root (keeps the worktree)";
        gwtc = "treeman worktree back --remove — cd to main root and drop the exited worktree if clean";
      };

      launcherBindings = lib.filter (b: launchers ? ${b.launcher}) [
        {
          key = "^[A";
          launcher = "tmux-lazy-docker";
        }
        {
          key = "^[t";
          launcher = "tmux-new-session";
        }
        {
          key = "^[g";
          launcher = "tmux-lazy-git";
        }
        {
          key = "^[a";
          launcher = "tmux-system-monitor";
        }
        {
          key = "^[f";
          launcher = "tmux-pick-project";
        }
        {
          key = "^[d";
          launcher = "tmux-pick-session";
        }
      ];

      zshFiles = {
        "funcs" = /* zsh */ ''
          ${lib.optionalString config.features.treeman ''
            typeset -gA _git_shorthand_docs=(
              ${lib.concatStringsSep "\n  " (
                lib.mapAttrsToList (name: doc: "${name} ${lib.escapeShellArg doc}") gitShorthandDocs
              )}
            )

            alias gcm='treeman git commit'
            alias gp='treeman git push'
            alias ga='treeman git add'
            alias gsd='treeman git diff'
            alias gst='treeman git status'
            alias gg='treeman git pull'
            alias gf='treeman git fetch'
            alias gsa='treeman git stash'
            alias gsp='treeman git stash pop'
            alias gcs='treeman git stash clear'
            alias gw='treeman git wipe'
            alias ggo='treeman git pull --pick'
            alias gl='treeman git log'

            gd()  { treeman git diff --pick "$@"; }
            gcd() { treeman git diff --pick --patch "$@"; }

            gcb() { local p; p=$(treeman git switch "$@") && [[ -n $p ]] && cd "$p"; }

            gwt() {
              if [[ $1 == - ]]; then
                local p; p=$(treeman worktree prev) && [[ -n $p ]] && cd "$p"
                return
              fi
              local p; p=$(treeman worktree switch "$@") && [[ -n $p ]] && cd "$p"
            }

            gwtd() { treeman worktree delete "$@"; }

            gwte() { local p; p=$(treeman worktree back)                && cd "''${p%%$'\n'*}"; }
            gwtc() { local p; p=$(treeman worktree back --remove --force) && cd "''${p%%$'\n'*}"; }
          ''}

          ${lib.optionalString (!onAndroid) ''
            function onport {
              ss -lptn " sport = :$1"
            }
          ''}

          function remote_passwd {
            local _user="$1" _host="$2"
            if [[ -z "$_user" || -z "$_host" ]]; then
              echo "usage: remote_passwd <user> <host>"
              return 1
            fi
            local _oldpass _newpass _confirm
            read -rs "_oldpass?Current password for $_user@$_host: "; echo
            read -rs "_newpass?New password: "; echo
            read -rs "_confirm?Confirm new password: "; echo
            if [[ "$_newpass" != "$_confirm" ]]; then
              echo "passwords do not match"
              return 1
            fi
            local _hash=$(${lib.getExe pkgs.openssl} passwd -6 "$_newpass") || return 1
            echo "$_oldpass" | ssh "$_user@$_host" "sudo -S -p ''' usermod -p '$_hash' '$_user'"
          }

          function fzf-project-picker {
            SELECTED_DIR="$(fzf-pick-project "$@")"
            if [[ -n "$SELECTED_DIR" ]]; then
              cd "$SELECTED_DIR"
            fi
            clear
          }
          function fzf-directory-picker {
            SELECTED_DIR="$(fzf-pick-directory "$@")"
            if [[ -n "$SELECTED_DIR" ]]; then
              cd "$SELECTED_DIR"
            fi
            clear
          }
        '';
        "aliases" = /* zsh */ ''
          alias la='ls -laF'
          alias ff='find . -type f -name'
          alias h='history'
          alias p='ps -f'
          alias sortnr='sort -n -r'
          alias rm='rm -i'
          alias cp='cp -i'
          alias mv='mv -i'
          alias pbcopy='clip'
          ${lib.optionalString config.features.desktop "alias pbpaste='${lib.getExe' pkgs.wl-clipboard "wl-paste"} --no-newline'"}
          alias gzcat='${lib.getExe' pkgs.gzip "gzip"} -dc'
          alias svim='nvim -u NONE'
          alias ls='eza'
        '';
        "settings" = /* zsh */ ''
          function _settings_init {
            bindkey "^Xa" _expand_alias

            autoload -Uz add-zsh-hook
            function _bind_run {
              local key=$1 cmd=$2
              local tag="''${key//[^A-Za-z0-9]/_}"
              local widget="_run_$tag" hook="_runhook_$tag"
              functions[$hook]="add-zsh-hook -d precmd $hook; ''${cmd}"
              functions[$widget]="add-zsh-hook precmd $hook; BUFFER='''; zle accept-line"
              zle -N "$widget"
              bindkey "$key" "$widget"
            }

            local _reload_cmd='[[ -n $TMUX ]] && tmux source-file "$HOME/.config/tmux/tmux.conf"; exec zsh'
            _bind_run "^[R" "$_reload_cmd"
            _bind_run "^[r" "$_reload_cmd"
            _bind_run "^[o" "nvim"
            _bind_run "^[O" "nvim ."
            ${lib.optionalString config.features.treeman ''
              function _git_shorthand_descriptions {
                (( CURRENT != 1 )) && return 1

                local -a git_cmds
                local func
                for func in "''${(@k)_git_shorthand_docs}"; do
                  git_cmds+=("''${func}:''${_git_shorthand_docs[$func]}")
                done

                _describe -t git-shortcuts 'git shortcuts' git_cmds
              }
            ''}

            zstyle ':completion:*' completer _expand _expand_alias ${lib.optionalString config.features.treeman "_git_shorthand_descriptions "}_complete _ignored
            zstyle ':completion:*' fzf-tab true
            zstyle ':completion:*' complete-options true
            zstyle ':completion:*' complete-aliases true
            zstyle ':completion:*' regular true
            zstyle ':completion:*' sort false
            zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

            zstyle ':completion:*:git-checkout:*' sort false
            zstyle ':completion:*:descriptions' format '[%d]'
            zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
            zstyle ':completion:*' menu no
            zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
            zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept --height=40% --reverse --info=inline
            zstyle ':fzf-tab:*' switch-group '<' '>'
            zstyle ':fzf-tab:*' fuzzy-search true

            HYPHEN_INSENSITIVE=false
            DISABLE_AUTO_TITLE=true
            VIM_MODE_NO_DEFAULT_BINDINGS=true
            KEYTIMEOUT=1
            ${lib.optionalString config.features.development "ARTISAN_OPEN_ON_MAKE_EDITOR=nvim"}
            ZSH_AUTOSUGGEST_MANUAL_REBIND=1
            ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20

            setopt COMPLETE_ALIASES

            ${lib.concatMapStringsSep "\n" (b: ''_bind_run "${b.key}" "${b.launcher}"'') launcherBindings}
            _bind_run "^[F" "fzf-project-picker"
            _bind_run "^[D" "fzf-directory-picker"

            unfunction _bind_run
          }
          _settings_init
          unfunction _settings_init
        '';
      }
      // lib.optionalAttrs config.features.treeman {
        "completions/_git_shortcuts" = /* zsh */ ''
          zmodload -F zsh/datetime p:EPOCHSECONDS

          _git_shortcuts() {
            case $service in
              gcb|gd|gcd|ggo|gwt)
                local now=$EPOCHSECONDS
                if (( now - ''${_gsc_br_time:-0} > 5 )) || [[ ''${_gsc_br_pwd:-} != $PWD ]]; then
                  local -a _refs
                  _refs=(''${(f)"$(git for-each-ref --format='%(refname:lstrip=2)' refs/heads 2>/dev/null
                    git for-each-ref --format='%(refname:lstrip=3)' refs/remotes 2>/dev/null)"})
                  typeset -ga _gsc_br_cache=(''${(u)_refs:#HEAD})
                  typeset -g _gsc_br_time=$now _gsc_br_pwd=$PWD
                fi
                local _cur=$(git branch --show-current 2>/dev/null)
                local -a _filtered=(''${_gsc_br_cache:#$_cur})
                _describe 'branches' _filtered
                ;;
              gwtd)
                local now=$EPOCHSECONDS
                if (( now - ''${_gsc_wt_time:-0} > 5 )) || [[ ''${_gsc_wt_pwd:-} != $PWD ]]; then
                  typeset -ga _gsc_wt_cache=(''${(f)"$(git worktree list --porcelain 2>/dev/null | sed -n 's|^branch refs/heads/||p')"})
                  typeset -g _gsc_wt_time=$now _gsc_wt_pwd=$PWD
                fi
                _describe 'worktrees' _gsc_wt_cache
                ;;
              gg|gf|gw)
                _arguments '1:flag:((--all\:"include\ all\ remotes/stash"))'
                ;;
              gwte|gwtc)
                return 0
                ;;
              *)
                return 1
                ;;
            esac
          }

          _git_shortcuts "$@"
        '';
      };

      sourceableZshFiles = lib.filter (n: !(lib.hasPrefix "completions/" n)) (lib.attrNames zshFiles);

      # The profile path, not a store path: stable across switches and GC.
      zshBin = "${config.home.profileDirectory}/bin/zsh";

      zshConfig =
        pkgs.runCommandLocal "stubbe-zsh-config"
          {
            nativeBuildInputs = [ pkgs.zsh ];
          }
          ''
            mkdir -p $out/completions
            ${lib.concatStrings (
              lib.mapAttrsToList (name: text: ''
                cp ${pkgs.writeText (baseNameOf name) text} $out/${name}
              '') zshFiles
            )}
            zsh -c 'for f in ${lib.concatStringsSep " " sourceableZshFiles}; do zcompile $out/$f; done'
          '';

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
      ]
      ++ lib.optionals config.features.development [
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
      ]
      ++ [
        {
          name = "zsh-vim-mode";
          src = inputs.zsh-vim-mode;
          file = "zsh-vim-mode.plugin.zsh";
        }
      ];

      zshPlugins = pkgs.runCommandLocal "stubbe-zsh-plugins" { nativeBuildInputs = [ pkgs.zsh ]; } (
        lib.concatMapStrings (p: ''
          mkdir -p $out/${p.name}
          cp -rT ${p.src} $out/${p.name}
          chmod -R u+w $out/${p.name}
          zsh -c 'zcompile $out/${p.name}/${p.file}'
        '') pluginSpecs
      );

      zshCompletions = pkgs.runCommandLocal "stubbe-zsh-completions" { } ''
        dir=$out/share/zsh/site-functions
        mkdir -p $dir
        ${lib.concatStrings (
          lib.mapAttrsToList (name: command: ''
            ${command} > $dir/${name}
          '') config.stubbe.zshCompletions
        )}
      '';

      profiles = [
        config.home.path
        config.nix.package
      ]
      ++ lib.optional (config.host.platform == "nixos") osConfig.system.path;

      nativeCompletionDirs = [
        "${zshConfig}/completions"
        "${zshCompletions}/share/zsh/site-functions"
      ]
      ++ map (p: "${p}/share/zsh/site-functions") profiles;

      bashCompleteFunction = pkgs.writeText "_bash_complete" /* zsh */ ''
        #autoload
        (( $+functions[_bash_compgen_files] )) || _bash_compgen_files() {
          local pattern=$word home=""
          if [[ $pattern == "~"* ]]; then
            home=''${~''${pattern%%/*}}
            pattern=$home''${pattern#"''${pattern%%/*}"}
          fi
          res=(''${(b)pattern}*($1N))
          [[ -n $home ]] && res=("''${word%%/*}''${^res#"$home"}")
        }

        (( $+functions[compgen] )) || compgen() {
          emulate -L zsh
          setopt extended_glob
          local name OPTARG OPTIND=1 word filter prefix="" suffix="" action
          local -a actions wordlists globs command_lines callbacks behaviours generated unfiltered res
          local -A action_names=(
            a alias b builtin c command d directory e export f file g group
            j job k keyword u user v variable
          )

          while getopts "o:A:G:W:C:F:P:S:X:abcdefgjkuv" name; do
            case $name in
              [abcdefgjkuv]) actions+=($action_names[$name]) ;;
              A) actions+=($OPTARG) ;;
              W) wordlists+=($OPTARG) ;;
              G) globs+=($OPTARG) ;;
              C) command_lines+=($OPTARG) ;;
              F) callbacks+=($OPTARG) ;;
              o) behaviours+=($OPTARG) ;;
              P) prefix=$OPTARG ;;
              S) suffix=$OPTARG ;;
              X) filter=$OPTARG ;;
              *) return 2 ;;
            esac
          done
          word=''${argv[OPTIND]-}

          for action in $actions; do
            case $action in
              alias) generated+=(''${(k)aliases}) ;;
              arrayvar) generated+=(''${(k)parameters[(R)array*]}) ;;
              binding) generated+=(''${(k)widgets}) ;;
              builtin) generated+=(''${(k)builtins}) ;;
              command) generated+=(''${(k)commands} ''${(k)aliases} ''${(k)builtins} ''${(k)functions} ''${(k)reswords}) ;;
              directory) _bash_compgen_files D-/; generated+=($res) ;;
              disabled) generated+=(''${(k)dis_builtins}) ;;
              enabled) generated+=(''${(k)builtins}) ;;
              export) generated+=(''${(k)parameters[(R)*export*]}) ;;
              file) _bash_compgen_files D; generated+=($res) ;;
              function) generated+=(''${(k)functions}) ;;
              group) res=(); _groups -U -O res; generated+=($res) ;;
              hostname) res=(); _hosts -U -O res; generated+=($res) ;;
              job) generated+=(''${savejobtexts%% *}) ;;
              keyword) generated+=(''${(k)reswords}) ;;
              signal) generated+=(SIG''${^signals}) ;;
              user) generated+=(''${(k)userdirs}) ;;
              variable) generated+=(''${(k)parameters}) ;;
              *) print -ru2 -- "compgen: unsupported action: $action"; return 2 ;;
            esac
          done

          for action in $wordlists; do
            () {
              emulate -L sh
              setopt braceexpand noglob ksharrays
              eval "res=($action)"
            }
            generated+=("''${res[@]}")
          done

          generated=(''${(M)generated:#''${(b)word}*})

          for action in $globs; do
            unfiltered+=(''${~action}(N))
          done
          for action in $callbacks; do
            local -a COMPREPLY=()
            () {
              emulate -L sh
              setopt kshglob noshglob braceexpand nokshautoload
              $action "$COMP_WORDS[1]" "$word" "$COMP_WORDS[COMP_CWORD]"
            }
            unfiltered+=("''${COMPREPLY[@]}")
          done
          for action in $command_lines; do
            unfiltered+=(''${(f)"$(eval "$action" '"$COMP_WORDS[1]"' '"$word"' '"$COMP_WORDS[COMP_CWORD]"')"})
          done
          generated+=($unfiltered)

          if (( ! $#generated )); then
            if (( behaviours[(Ie)default] || behaviours[(Ie)bashdefault] )); then
              _bash_compgen_files D; generated=($res)
            elif (( behaviours[(Ie)dirnames] )); then
              _bash_compgen_files D-/; generated=($res)
            fi
          fi
          if (( behaviours[(Ie)plusdirs] )); then
            _bash_compgen_files D-/; generated+=($res)
          fi

          if [[ -n $filter ]]; then
            setopt kshglob
            local pattern=''${filter//(#b)(\\|)\&/''${''${match[1]:+\\&}:-''${(b)word}}}
            if [[ $pattern == "!"* ]]; then
              generated=(''${(M)generated:#''${~pattern#!}})
            else
              generated=(''${generated:#''${~pattern}})
            fi
          fi

          (( $#generated )) && print -rl -- ''${''${generated/#/$prefix}/%/$suffix}
          return 0
        }

        (( $+functions[compopt] )) || compopt() {
          emulate -L zsh
          while (( $# )); do
            case $1 in
              -o) bash_options[$2]=1; shift 2 ;;
              +o) unset "bash_options[$2]"; shift 2 ;;
              *) shift ;;
            esac
          done
          return 0
        }

        local function_name ret=1
        local -a actions suffix matches
        local -A bash_options savejobtexts
        local -x COMP_POINT COMP_CWORD COMP_LINE="$words"
        local -a COMP_WORDS COMPREPLY BASH_VERSINFO

        (( COMP_POINT = 1 + ''${#''${(j. .)words[1,CURRENT-1]}} + $#QIPREFIX + $#IPREFIX + $#PREFIX ))
        (( COMP_CWORD = CURRENT - 1 ))
        COMP_WORDS=("''${words[@]}")
        BASH_VERSINFO=(2 05b 0 1 release)
        savejobtexts=(''${(kv)jobtexts})

        while (( $# )); do
          case $1 in
            -F) function_name=$2; shift 2 ;;
            -o) bash_options[$2]=1; shift 2 ;;
            -[AGWCXPS]) actions+=("$1" "$2"); shift 2 ;;
            *) actions+=("$1"); shift ;;
          esac
        done

        if [[ -n $function_name ]]; then
          () {
            local -a args=("$words[1]" "$words[CURRENT]" "$words[CURRENT-1]")
            typeset -h words
            emulate -L sh
            setopt kshglob noshglob braceexpand nokshautoload
            $function_name "''${args[@]}"
          }
          matches=("''${COMPREPLY[@]}")
        fi
        (( $#actions )) && matches+=(''${(f)"$(compgen "''${actions[@]}" -- "$words[CURRENT]")"})

        (( $+bash_options[nospace] )) && suffix=(-S ''')

        if (( $#matches )); then
          if (( $+bash_options[filenames] )); then
            compset -P '*/' && matches=(''${matches##*/})
            compset -S '/*' && matches=(''${matches%%/*})
            compadd -f "''${suffix[@]}" -a matches && ret=0
          else
            compadd "''${suffix[@]}" - "''${(@)''${(Q@)matches}:#*\ }" && ret=0
            compadd -S ' ' - ''${''${(M)''${(Q)matches}:#*\ }% } && ret=0
          fi
        fi

        if (( ret )); then
          if (( $+bash_options[default] || $+bash_options[bashdefault] )); then
            _default "''${suffix[@]}" && ret=0
          elif (( $+bash_options[dirnames] )); then
            _directories "''${suffix[@]}" && ret=0
          fi
        fi
        (( $+bash_options[plusdirs] )) && _directories "''${suffix[@]}" && ret=0

        return ret
      '';

      bashCompletionProbe = pkgs.writeText "bash-completion-probe.bash" /* bash */ ''
        compopt() {
          return 0
        }

        # shellcheck source=/dev/null
        source "$1" >/dev/null 2>&1
        spec=$(complete -p -- "$2" 2>/dev/null) || exit 0
        eval "spec=(''${spec#complete })"
        unset 'spec[-1]'

        func=
        actions=()
        while ((''${#spec[@]})); do
          case ''${spec[0]} in
          -F)
            func=''${spec[1]}
            spec=("''${spec[@]:2}")
            ;;
          -o)
            spec=("''${spec[@]:2}")
            ;;
          -[AGWCXPS])
            actions+=("''${spec[@]:0:2}")
            spec=("''${spec[@]:2}")
            ;;
          -[DEI])
            spec=("''${spec[@]:1}")
            ;;
          *)
            actions+=("''${spec[0]}")
            spec=("''${spec[@]:1}")
            ;;
          esac
        done

        while read -r name; do
          printf 'names\t%s\n' "$name"
        done < <(compgen -b -k -a -A function)

        while IFS=$'\t' read -r i pre cur; do
          read -ra COMP_WORDS <<<"$pre"
          COMP_WORDS+=("$cur")
          COMP_CWORD=$((''${#COMP_WORDS[@]} - 1))
          COMP_LINE="''${COMP_WORDS[*]}"
          COMP_POINT=''${#COMP_LINE}
          COMPREPLY=()
          [[ -n $func ]] && "$func" "$2" "$cur" "''${COMP_WORDS[COMP_CWORD - 1]}" </dev/null >/dev/null
          results=("''${COMPREPLY[@]}")
          ((''${#actions[@]})) && mapfile -t -O "''${#results[@]}" results < <(compgen "''${actions[@]}" -- "$cur")
          for r in "''${results[@]}"; do
            printf '%s\t%s\n' "$i" "$r"
          done
        done
      '';

      zshCompletionProbe = pkgs.writeText "zsh-completion-probe.zsh" /* zsh */ ''
        fpath=($1 $fpath)
        autoload -Uz _bash_complete _bash_$2

        compadd() {
          local -a found
          while (( $# )); do
            case $1 in
              -a) found+=(''${(P)2}); shift 2 ;;
              -[SPJXo]) shift 2 ;;
              -) shift; found+=("$@"); break ;;
              -*) shift ;;
              *) found+=("$1"); shift ;;
            esac
          done
          (( $#found )) && print -rl -- ''${found/#/$i$'\t'}
          return 0
        }
        compset() { return 1 }
        _default() { return 1 }
        _directories() { return 1 }

        while IFS=$'\t' read -r i pre cur; do
          words=(''${(s: :)pre} "$cur")
          CURRENT=$#words
          PREFIX=$cur IPREFIX="" QIPREFIX=""
          _bash_$2 </dev/null
        done

        tab=$'\t'
        print -rl -- names$tab''${^''${(k)builtins}} names$tab''${^''${(k)reswords}} names$tab''${^''${(k)functions}} names$tab''${^''${(k)aliases}}
        exit 0
      '';

      bashCompletionBridge =
        pkgs.runCommandLocal "stubbe-zsh-bash-bridge" { nativeBuildInputs = [ pkgs.zsh ]; }
          ''
            export HOME=$TMPDIR
            zsh -f <<'ZSHEOF'
            setopt err_exit pipe_fail extended_glob
            export LC_ALL=C
            path=(${lib.concatMapStringsSep " " (p: "${p}/bin") profiles} $path)
            fpath=(${lib.concatStringsSep " " nativeCompletionDirs} $fpath)
            autoload -Uz compinit bashcompinit
            compinit -u -D
            bashcompinit
            mkdir -p $out

            cp ${bashCompleteFunction} $out/_bash_complete

            translate() {
              (
                local name=$1 script=$2 p f line
                local -a before_parameters before_names after redefined
                local -A before_functions
                before_functions=("''${(@kv)functions}")
                before_names=(''${(k)before_functions})
                before_parameters=(''${(k)parameters})
                source $script >/dev/null 2>$TMPDIR/source-errors
                [[ ! -s $TMPDIR/source-errors ]] || { print -ru2 -- "sourcing fails: $(head -n1 $TMPDIR/source-errors)"; exit 1 }
                [[ $_comps[$name] == "_bash_complete "* ]] || { print -ru2 -- "registers no completion under bashcompinit"; exit 1 }
                for f in $before_names; do
                  [[ $functions[$f] == $before_functions[$f] ]] || redefined+=($f)
                done
                (( ! $#redefined )) || { print -ru2 -- "redefines existing zsh functions: $redefined"; exit 1 }
                print -r -- "#compdef $name"
                after=(''${(k)parameters})
                for p in ''${(o)after:|before_parameters}; do
                  [[ $parameters[$p] == *special* ]] && continue
                  line=$(typeset -p -- $p)
                  print -r -- "typeset -g ''${line#(typeset|export) }"
                done
                after=(''${(k)functions})
                for f in ''${(o)after:|before_names}; do
                  functions -- $f
                done
                print -r -- $_comps[$name]
              )
            }

            typeset -a probe_pre probe_cur

            write_probes() {
              local i
              for i in {1..$#probe_cur}; do
                print -r -- "$i"$'\t'"$probe_pre[i]"$'\t'"$probe_cur[i]"
              done > $TMPDIR/probes
            }

            typeset -A shell_names

            collect_shell_names() {
              local line
              shell_names=()
              for line in ''${(M)''${(f)"$(<$TMPDIR/expected)"}:#names$'\t'*} ''${(M)''${(f)"$(<$TMPDIR/actual)"}:#names$'\t'*}; do
                shell_names[''${line#names$'\t'}]=1
              done
            }

            normalize() {
              local line idx val
              local -a kept
              while IFS= read -r line; do
                idx=''${line%%$'\t'*}
                val=''${''${line#*$'\t'}%%[[:space:]]##}
                if [[ $idx == names ]]; then
                  continue
                elif [[ $idx != <1-> || $line != *$'\t'* ]]; then
                  kept+=("stray"$'\t'"$line")
                elif (( ! $+shell_names[$val] )) && [[ $val == ''${(b)probe_cur[idx]}* ]]; then
                  kept+=("$idx"$'\t'"$val")
                fi
              done < $1
              print -rl -- ''${(ou)kept}
            }

            run_bash() {
              timeout 20 ${lib.getExe pkgs.bashInteractive} --norc --noprofile ${bashCompletionProbe} $1 $2 < $TMPDIR/probes > $TMPDIR/expected 2>$TMPDIR/bash-errors
            }

            run_zsh() {
              timeout 20 zsh -f ${zshCompletionProbe} $out $1 < $TMPDIR/probes > $TMPDIR/actual 2>$TMPDIR/zsh-errors
            }

            verify() {
              local name=$1 script=$2 word expected actual
              probe_pre=($name $name $name)
              probe_cur=("" - --)
              write_probes
              run_bash $script $name || { REPLY="bash reference failed"; return 1 }
              for word in ''${''${''${(f)"$(normalize $TMPDIR/expected)"}#*$'\t'}[1,2]}; do
                [[ $word == [^[:space:]]## ]] || continue
                probe_pre+=("$name $word")
                probe_cur+=("")
              done
              write_probes
              run_bash $script $name || { REPLY="bash reference failed"; return 1 }
              run_zsh $name || { REPLY="zsh translation failed"; return 1 }
              local -a bash_errors=(''${(ou)''${(f)"$(<$TMPDIR/bash-errors)"}}) zsh_errors=(''${(ou)''${(f)"$(<$TMPDIR/zsh-errors)"}})
              local -a zsh_only=(''${zsh_errors:|bash_errors}) bash_only=(''${bash_errors:|zsh_errors})
              (( ! $#zsh_only && ! $#bash_only )) || { REPLY="stderr differs from bash: ''${zsh_only[1]:-bash alone printed: $bash_only[1]}"; return 1 }
              collect_shell_names
              expected=$(normalize $TMPDIR/expected)
              actual=$(normalize $TMPDIR/actual)
              [[ -n $expected ]] || { REPLY="bash completes nothing to verify against"; return 1 }
              [[ $expected == $actual ]] || { REPLY="zsh results differ from bash"; return 1 }
            }

            bridge() {
              local name=$1 script=$2 stub=$out/_bash_$1
              translate $name $script > $stub 2>$TMPDIR/translate-errors || { rm -f $stub; REPLY=$(<$TMPDIR/translate-errors); return 1 }
              verify $name $script || { rm -f $stub; return 1 }
            }

            typeset -A seen
            for dir in ${lib.concatMapStringsSep " " (p: "${p}/share/bash-completion/completions") profiles}; do
              [[ -d $dir ]] || continue
              for script in $dir/*(N-.); do
                name=''${''${script:t}%.bash}
                (( $+seen[$name] || $+_comps[$name] )) && continue
                [[ -x $dir/../../../bin/$name ]] || continue
                seen[$name]=1
                bridge $name ''${script:A} || print -r -- "bash-bridge: skipped $name: $REPLY"
              done
            done

            for script in $out/_*(N); do
              zcompile $script
            done
            ZSHEOF
          '';

      # Interpolated into both the .zshrc and the zcompdump builder, so runtime
      # and dump-build fpath cannot diverge.
      fpathLine = "fpath=(${
        lib.concatStringsSep " " (nativeCompletionDirs ++ [ "${bashCompletionBridge}" ])
      } $fpath)";

      # Output is a directory because zcompile writes the .zwc next to
      # init.zsh, which must stay inside $out.
      mkInit =
        name: script:
        "${
          pkgs.runCommandLocal "zsh-${name}-init" { nativeBuildInputs = [ pkgs.zsh ]; } ''
            mkdir -p $out
            ${script}
            zsh -c 'zcompile $out/init.zsh'
          ''
        }/init.zsh";

      # Frees Tab for fzf-tab and Ctrl-R for atuin. The `zle -N` widget lines
      # have to stay or the `if` blocks fzf wraps the bindings in are left empty.
      fzfInit = mkInit "fzf" ''
        ${lib.getExe pkgs.fzf} --zsh \
          | grep -Fv "bindkey '^I'" \
          | grep -v 'bindkey.*fzf-cd-widget' \
          | grep -v 'bindkey.*fzf-history-widget' > $out/init.zsh
      '';

      atuinInit = mkInit "atuin" ''
        HOME=$TMPDIR ${lib.getExe config.programs.atuin.package} init zsh \
          ${lib.escapeShellArgs config.programs.atuin.flags} > $out/init.zsh
      '';

      historyFile = "${config.home.homeDirectory}/.zsh_history";
      atuinDatabase = "${config.xdg.dataHome}/atuin/history.db";

      starshipInit = mkInit "starship" ''
        HOME=$TMPDIR ${lib.getExe pkgs.starship} init zsh --print-full-init > $out/init.zsh
      '';

      zoxideInit = mkInit "zoxide" ''
        ${lib.getExe pkgs.zoxide} init zsh > $out/init.zsh
      '';

      # The hook calls direnv-instant by name, so it resolves to the wrapper
      # programs.direnv-instant installs (modules/development.nix), which
      # carries the settings.
      direnvInstantInit = mkInit "direnv-instant" ''
        ${lib.getExe config.programs.direnv-instant.package} hook zsh > $out/init.zsh
      '';

      # -u because the sandbox build user fails compaudit's ownership check,
      # which is irrelevant at runtime.
      zcompdump = pkgs.runCommandLocal "stubbe-zcompdump" { nativeBuildInputs = [ pkgs.zsh ]; } ''
        mkdir -p $out
        export HOME=$TMPDIR
        zsh -f <<'ZSHEOF'
        ${fpathLine}
        autoload -Uz compinit
        compinit -u -d "$out/zcompdump"
        ${lib.optionalString config.features.treeman ''
          {
            print -r -- "autoload -Uz _git_shortcuts"
            print -r -- "compdef _git_shortcuts ${lib.concatStringsSep " " (lib.attrNames gitShorthandDocs)}"
          } >> "$out/zcompdump"
        ''}
        zcompile "$out/zcompdump"
        ZSHEOF
      '';

      sourcePlugins = lib.concatMapStringsSep "\n" (
        p: "source ${zshPlugins}/${p.name}/${p.file}"
      ) pluginSpecs;
    in
    {
      options.stubbe.zshCompletions = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Generated zsh completion functions, keyed by file name (`_<cmd>`): each
          value is a shell command that prints the completion script. Each
          aspect registers the completion of the tool it installs.
        '';
      };

      config = {
        home.packages = with pkgs; [
          zsh-completions
          zsh-patina
          starship
        ];

        # Terminals and tmux spawn $SHELL. Pointing it at the nix zsh skips the
        # distro-zsh hop through the .zshenv exec below; logins via passwd (TTY,
        # ssh) still take that hop.
        home.sessionVariables.SHELL = zshBin;

        programs.zsh = {
          enable = true;
          enableCompletion = true;
          completionInit = ''
            autoload -Uz compinit
            compinit -C -d ${zcompdump}/zcompdump
          '';
          # Sourced from .zshenv, before Ubuntu's /etc/zsh/zshrc can run its own
          # compinit against the system fpath. The no_aliases line is the alias
          # guard for AI agents: their tool shells are non-interactive zsh that
          # source a snapshot re-defining every alias (rm -i, cp -i, ls=eza, the
          # treeman git wrappers), which then hijack the commands they run. zshenv
          # is read before the -c command, and the option survives the snapshot,
          # so the definitions stay but never expand. Interactive shells - a real
          # terminal, or a pty the human is driving - keep their aliases.
          #
          # The exec swaps an interactive distro zsh for the nix one: fzf-tab's
          # compiled module links nix glibc and fails to load into a host-glibc
          # zsh. Done here, not via chsh, so a broken profile leaves you in the
          # distro zsh instead of locked out. argv0 carries login-ness across.
          # No-op on NixOS, where the running zsh is already a store path.
          envExtra = ''
            [[ -o interactive && -z $ZSH_EXECUTION_STRING && -x ${zshBin} \
              && ''${''${:-/proc/$$/exe}:A} != /nix/store/* ]] &&
              exec -a "$ZSH_ARGZERO" ${zshBin} -i
            skip_global_compinit=1
            [[ -o interactive ]] || setopt no_aliases
          '';
          history = {
            path = historyFile;
            size = 10000;
            save = 10000;
            extended = true;
            share = true;
            append = true;
            ignoreAllDups = true;
          };
          initContent = lib.mkMerge [
            (lib.mkOrder 500 ''
              source ${zshConfig}/funcs
              ${fpathLine}
            '')
            # fzf-tab must load right after compinit and patina last, so its ZLE
            # hooks wrap the final widget set.
            (lib.mkOrder 1000 ''
              source ${zshConfig}/aliases
              ${sourcePlugins}
              source ${zshConfig}/settings
              source ${fzfInit}
              source ${atuinInit}
              source ${starshipInit}
              source ${zoxideInit}
              ${lib.optionalString config.programs.direnv-instant.enable "source ${direnvInstantInit}"}
              _patina_init="${config.xdg.cacheHome}/zsh/patina-init.zsh"
              [[ -f "$_patina_init" ]] && source "$_patina_init"
              unset _patina_init
            '')
          ];
        };

        programs.atuin = {
          enable = true;
          enableZshIntegration = false;
          flags = [
            "--disable-up-arrow"
            "--disable-ai"
          ];
          settings = {
            db_path = atuinDatabase;
            update_check = false;
            auto_sync = false;
            style = "compact";
            inline_height = 20;
            show_help = false;
            show_tabs = false;
            show_preview = false;
            show_numeric_shortcuts = false;
            ui = {
              columns = [ "command" ];
              syntax_highlight = false;
            };
            theme.name = "catppuccin-fzf";
          };
          themes.catppuccin-fzf = {
            theme.name = "catppuccin-fzf";
            colors = with pkgs.stubbe.withHash; {
              Base = text;
              AlertError = mauve;
              AlertWarn = red;
              AlertInfo = green;
              Annotation = overlay1;
              Guidance = overlay1;
              Important = red;
              Title = mauve;
              Muted = overlay0;
            };
          };
        };

        stubbe.setup.atuinImport = {
          after = [ "linkGeneration" ];
          script = ''
            if [[ ! -e '${atuinDatabase}' && -f '${historyFile}' ]]; then
              ATUIN_SESSION="$(${lib.getExe config.programs.atuin.package} uuid)" \
                HISTFILE='${historyFile}' \
                ${lib.getExe config.programs.atuin.package} import zsh
            fi
          '';
        };

        stubbe.setup.zshPatina.script = ''
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          _patina_cache='${config.xdg.cacheHome}/zsh'
          mkdir -p "$_patina_cache"
          if ${lib.getExe pkgs.zsh-patina} activate > "$_patina_cache/patina-init.zsh.tmp"; then
            mv "$_patina_cache/patina-init.zsh.tmp" "$_patina_cache/patina-init.zsh"
            ${lib.getExe pkgs.zsh} -c 'zcompile "$1"' _ "$_patina_cache/patina-init.zsh"
          else
            rm -f "$_patina_cache/patina-init.zsh.tmp"
            echo "zsh-patina activate failed; syntax highlighting stays off" >&2
          fi
          unset _patina_cache
        '';

        # The hook script is generated at switch time, not built: `zsh-patina
        # activate` embeds $XDG_RUNTIME_DIR and starts the daemon. That generated
        # script never starts the daemon itself, so without this unit highlighting
        # silently does nothing after a reboot.
        systemd.user.services.zsh-patina = {
          Unit.Description = "zsh-patina syntax highlighting daemon";
          Service = {
            ExecStart = "${lib.getExe pkgs.zsh-patina} start --no-daemon";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };
}
