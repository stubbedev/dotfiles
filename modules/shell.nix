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

      hmSpec = pkgs.stubbe.hm;

      zshFiles = {
        "apaths" = ''

          function _apaths_init {
            local -a STUBBE_APP_PATHS=(
              "$HOME/.local/share/applications"
              "$HOME/.local/share/flatpak/exports/share"
            )
            local -a new_apaths=()
            local _ap
            for _ap in "''${STUBBE_APP_PATHS[@]}"; do
              [[ -d "$_ap" ]] || continue
              [[ ":$XDG_DATA_DIRS:" == *":$_ap:"* ]] && continue
              new_apaths+=("$_ap")
            done
            (( ''${#new_apaths} )) && XDG_DATA_DIRS="''${(j/:/)new_apaths}:$XDG_DATA_DIRS"
            export XDG_DATA_DIRS
          }
          _apaths_init
          unfunction _apaths_init
        '';
        "sysfuncs" = ''
          # shellcheck disable=SC1091

          function is_binary {
            command -v "$1" &>/dev/null
          }

          function are_binary {
            local arg
            for arg in "$@"; do
              is_binary "$arg" || return 1
            done
          }

          function is_file {
            [[ -f "$1" ]]
          }

          function src_zsh {
            exec zsh
          }
        '';
        "funcs" = ''
          # shellcheck disable=SC1091


          typeset -gA _git_shorthand_docs=(
            gcm 'treeman git commit — auto ticket prefix; trailing \ opens editor'
            gp 'treeman git push — warns on protected/diverged branches'
            gcb 'treeman git switch — checkout/create branch, worktree-aware (cd)'
            ga 'treeman git add — interactive stage picker'
            gsd 'treeman git diff — working-tree diff'
            gd 'treeman git diff --pick — three-dot diff vs a picked branch'
            gcd 'treeman git diff --pick --patch — export three-dot diff to a file'
            gst 'treeman git status — short status'
            gg 'treeman git pull — current branch (--all for all)'
            gf 'treeman git fetch (--all for all remotes)'
            gsa 'treeman git stash — stash all local changes'
            gcs 'treeman git stash clear — drop the entire stash stack'
            gw 'treeman git wipe — stash + drop local changes (--all clears stack)'
            ggo 'treeman git pull --pick — pull a selected origin branch'
            gl 'treeman git log — interactive log (cherry-pick/revert/copy)'
            gsp 'treeman git stash pop — pick a stash to pop'
            gwt 'treeman worktree switch — switch/create a branch worktree (cd; `-` toggles previous)'
            gwtd 'treeman worktree delete — remove a worktree (picker with no arg)'
            gwte 'treeman worktree back — cd to main repo root (keeps the worktree)'
            gwtc 'treeman worktree back --remove — cd to main root and drop the exited worktree if clean'
          )

          function in_git_repo {
            local dir=$PWD
            while [[ $dir != / ]]; do
              [[ -e $dir/.git ]] && { _git_root=$dir; return 0; }
              dir=''${dir:h}
            done
            return 1
          }

          function _in_linked_worktree {
            [[ -f "$_git_root/.git" ]]
          }

          if are_binary git treeman; then
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
          fi

          if is_binary ss; then
            function onport {
              ss -lptn " sport = :$1"
            }
          fi

          if are_binary ssh openssl; then
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
              local _hash=$(openssl passwd -6 "$_newpass") || return 1
              echo "$_oldpass" | ssh "$_user@$_host" "sudo -S -p ''' usermod -p '$_hash' '$_user'"
            }
          fi

          if is_binary uv; then
            function pysrc {
              if ! is_file "$PWD/venv/bin/activate"; then
                uv venv ./venv
              fi
              is_file "$PWD/venv/bin/activate" && source "$PWD/venv/bin/activate"
            }
          fi

          if is_binary fzf; then
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
          fi
        '';
        "aliases" = ''
          alias la='ls -laF'
          alias ff='find . -type f -name'
          alias h='history'
          alias p='ps -f'
          alias sortnr='sort -n -r'
          alias rm='rm -i'
          alias cp='cp -i'
          alias mv='mv -i'

          if is_binary clip; then
            alias pbcopy='clip'
          elif is_binary xclip; then
            alias pbcopy='xclip -selection clipboard'
          fi

          if is_binary wl-paste; then
            alias pbpaste='wl-paste --no-newline'
          elif is_binary xclip; then
            alias pbpaste='xclip -selection clipboard -o'
          fi

          if is_binary gzip; then
            alias gzcat='gzip -dc'
          fi

          if is_binary nvim; then
            alias svim='nvim -u NONE'
          fi

          if is_binary eza; then
            alias ls='eza'
          else
            alias ls='ls --color'
          fi
        '';
        "settings" = ''
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

            local _reload_cmd='[[ -n $TMUX ]] && tmux source-file "$HOME/.config/tmux/tmux.conf"; src_zsh'
            _bind_run "^[R" "$_reload_cmd"
            _bind_run "^[r" "$_reload_cmd"
            _bind_run "^[o" "nvim"
            _bind_run "^[O" "nvim ."
            function _git_shorthand_descriptions {
              (( CURRENT != 1 )) && return 1
              (( ''${#_git_shorthand_docs} == 0 )) && return 1

              local -a git_cmds
              local func
              for func in "''${(@k)_git_shorthand_docs}"; do
                git_cmds+=("''${func}:''${_git_shorthand_docs[$func]}")
              done

              _describe -t git-shortcuts 'git shortcuts' git_cmds
            }

            zstyle ':completion:*' completer _expand _expand_alias _git_shorthand_descriptions _complete _ignored
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
            if is_binary eza; then
                zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
            fi
            zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept --height=40% --reverse --info=inline
            zstyle ':fzf-tab:*' switch-group '<' '>'
            zstyle ':fzf-tab:*' fuzzy-search true

            function _avahi_ssh_hosts {
              local cache="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh-avahi-hosts"
              if [[ -s $cache ]]; then
                reply=( ''${(f)"$(<$cache)"} )
              else
                reply=()
              fi
            }
            zstyle -e ':completion:*:hosts' hosts '_avahi_ssh_hosts'

            HYPHEN_INSENSITIVE=false
            DISABLE_AUTO_TITLE=true
            VIM_MODE_NO_DEFAULT_BINDINGS=true
            KEYTIMEOUT=1
            ARTISAN_OPEN_ON_MAKE_EDITOR=nvim
            ZSH_AUTOSUGGEST_MANUAL_REBIND=1
            ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20

            setopt COMPLETE_ALIASES

            _bind_run "^[A" "tmux-lazy-docker"
            _bind_run "^[t" "tmux-new-session"
            _bind_run "^[g" "tmux-lazy-git"
            _bind_run "^[a" "tmux-system-monitor"

            if is_binary fzf; then
                _bind_run "^[f" "tmux-pick-project"
                _bind_run "^[F" "fzf-project-picker"
                _bind_run "^[d" "tmux-pick-session"
                _bind_run "^[D" "fzf-directory-picker"
            fi

            if is_binary pyenv; then
                export PYENV_ROOT="$HOME/.pyenv"
                [[ ":$PATH:" == *":$PYENV_ROOT/bin:"* ]]    || PATH="$PYENV_ROOT/bin:$PATH"
                [[ ":$PATH:" == *":$PYENV_ROOT/shims:"* ]] || PATH="$PYENV_ROOT/shims:$PATH"
                function pyenv {
                    unfunction pyenv
                    eval "$(command pyenv init -)"
                    eval "$(command pyenv virtualenv-init -)"
                    pyenv "$@"
                }
            fi

            unfunction _bind_run
          }
          _settings_init
          unfunction _settings_init
        '';
        "completions/_git_shortcuts" = ''
          _git_shortcuts() {
            case $service in
              gcb|gd|gcd|ggo|gwt)
                local now=$EPOCHSECONDS
                if (( now - ''${_gsc_br_time:-0} > 5 )) || [[ ''${_gsc_br_pwd:-} != $PWD ]]; then
                  _list_git_branches
                  typeset -ga _gsc_br_cache=("''${reply[@]}")
                  typeset -g _gsc_br_time=$now _gsc_br_pwd=$PWD
                fi
                local _cur=$(git branch --show-current 2>/dev/null)
                local -a _filtered=()
                local _b
                for _b in "''${_gsc_br_cache[@]}"; do
                  [[ "$_b" == "$_cur" ]] && continue
                  _filtered+=("$_b")
                done
                _describe 'branches' _filtered
                ;;
              gwtd)
                local now=$EPOCHSECONDS
                if (( now - ''${_gsc_wt_time:-0} > 5 )) || [[ ''${_gsc_wt_pwd:-} != $PWD ]]; then
                  local -a _wt_list=()
                  local _path _branch
                  while IFS=$'\t' read -r _path _branch; do
                    _wt_list+=("$_branch")
                  done < <(_list_worktrees)
                  typeset -ga _gsc_wt_cache=("''${_wt_list[@]}")
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
        "completions/_hm" = ''
          #compdef hm

          _hm() {
            local context state line
            typeset -A opt_args

            local -i _hm_is_nixos=0
            if [[ -r /etc/os-release ]] && grep -q '^ID=nixos' /etc/os-release; then
              _hm_is_nixos=1
            fi

            local -a commands
            commands=(
              ${hmSpec.renderZsh "    " "all"}
            )

            if (( _hm_is_nixos )); then
              commands+=(
                ${hmSpec.renderZsh "      " "nixos"}
              )
            else
              commands+=(
                ${hmSpec.renderZsh "      " "standalone"}
              )
            fi

            local -a global_opts
            global_opts=(
              '(-f --file)'{-f,--file}'[The home configuration file]:file:_files'
              '(-A --attribute)'{-A,--attribute}'[Optional attribute that selects a configuration expression]:attribute:'
              '(-I --include)'{-I,--include}'[Add a path to the Nix expression search path]:path:_directories'
              '--flake[Use Home Manager configuration at flake-uri]:flake-uri:'
              '(-b --backup)'{-b,--backup}'[Move existing files to new path rather than fail]:extension:'
              '(-v --verbose)'{-v,--verbose}'[Verbose output]'
              '(-n --dry-run)'{-n,--dry-run}'[Do a dry run, only prints what actions would be taken]'
              '(-h --help)'{-h,--help}'[Print help]'
              '--version[Print the Home Manager version]'
              '--arg[Override inputs passed to home-manager.nix]:name: :value:'
              '--argstr[Override inputs passed to home-manager.nix (string)]:name: :value:'
              '--cores[Number of cores to use]:cores:'
              '--debug[Enable debug mode]'
              '--impure[Allow impure evaluation]'
              '--keep-failed[Keep failed builds]'
              '--keep-going[Keep going on build failures]'
              '(-j --max-jobs)'{-j,--max-jobs}'[Maximum number of jobs]:jobs:'
              '--option[Set Nix option]:name: :value:'
              '(-L --print-build-logs)'{-L,--print-build-logs}'[Print build logs]'
              '--log-format[Set log format]:format:(raw internal-json bar bar-with-logs)'
              '--show-trace[Show trace on errors]'
              '--substitute[Enable substitution]'
              '--no-substitute[Disable substitution]'
              '--no-out-link[Do not create a symlink to the output path]'
              '--no-write-lock-file[Do not write lock file]'
              '--builders[Builders to use]:builders:'
              '--refresh[Consider all previously downloaded files out-of-date]'
            )

            _arguments -C \
              "$global_opts" \
              '1: :->command' \
              '*:: :->args' \
              && return 0

            case $state in
              command)
                _describe -t commands 'hm commands' commands
                ;;
              args)
                case $words[1] in
                  option)
                    _message 'configuration option name'
                    ;;
                  remove-generations)
                    local -a generations
                    if (( ''${+commands[home-manager]} )); then
                      generations=(''${(f)"$(home-manager generations 2>/dev/null | grep -o '^[0-9]\+' || true)"})
                      if [[ ''${#generations} -gt 0 ]]; then
                        _describe 'generation IDs' generations
                      else
                        _message 'generation ID'
                      fi
                    else
                      _message 'generation ID'
                    fi
                    ;;
                  expire-generations)
                    _message 'timestamp (e.g., "-30 days" or "2018-01-01")'
                    ;;
                  init)
                    _arguments \
                      '--switch[Immediately activate the generated configuration]' \
                      '1:directory:_directories'
                    ;;
                  iso)
                    local -a iso_cmds
                    iso_cmds=(
                      ${hmSpec.renderSubZsh "            " "iso"}
                    )
                    case $words[2] in
                      burn)
                        _arguments \
                          '--yes[Confirm destructive write to device]' \
                          '-y[Confirm destructive write to device]' \
                          '--rebuild[Force a fresh ISO build even if result is cached]' \
                          '*:block device:->blockdev'
                        if [[ $state == blockdev ]]; then
                          local -a devs
                          devs=(''${(f)"$(lsblk -d -n -o NAME,SIZE,TRAN 2>/dev/null | awk '$3 == "usb" {print "/dev/"$1":("$2")"}')"})
                          if (( ''${#devs} )); then
                            _describe -t block-devices 'USB device' devs
                          else
                            _message 'USB block device (e.g. /dev/sdb)'
                          fi
                        fi
                        ;;
                      build|path)
                        _arguments \
                          '--rebuild[Force a fresh build even if output is already in the store]' \
                          '(-L --print-build-logs)'{-L,--print-build-logs}'[Print build logs]' \
                          '--show-trace[Show trace on errors]'
                        ;;
                      ''')
                        _describe -t iso-commands 'iso command' iso_cmds
                        ;;
                      *)
                        case $CURRENT in
                          2) _describe -t iso-commands 'iso command' iso_cmds ;;
                        esac
                        ;;
                    esac
                    return 0
                    ;;
                  ${hmSpec.plainVerbs})
                    return 0
                    ;;
                  gc)
                    _arguments \
                      '-d[Delete old generations of all profiles]' \
                      '--delete-old[Delete old generations of all profiles]' \
                      '--delete-older-than[Delete generations older than DURATION]:duration:' \
                      '--dry-run[Print what would be deleted, do not delete]'
                    return 0
                    ;;
                  trust)
                    case $CURRENT in
                      2) _message 'machine name (or pubkey alone for auto-name)' ;;
                      3) _message 'age recipient pubkey (age1...)' ;;
                    esac
                    return 0
                    ;;
                  secret)
                    case $CURRENT in
                      2)
                        local -a actions
                        actions=(
                          ${hmSpec.renderSubZsh "                " "secret"}
                        )
                        _describe -t actions 'secret action' actions
                        ;;
                      3)
                        local flake_dir="''${HM_FLAKE_DIR:-$HOME/.stubbe}"
                        if [[ -L "$flake_dir" ]]; then
                          flake_dir=$(readlink -f "$flake_dir")
                        fi
                        local -a names
                        if [[ -d "$flake_dir/secrets" ]]; then
                          names=(''${(f)"$(cd "$flake_dir/secrets" && print -l *(N.))"})
                        fi
                        if (( ''${#names} )); then
                          _describe -t secrets 'secret file' names
                        else
                          _message 'secret name (e.g. github-token)'
                        fi
                        ;;
                    esac
                    return 0
                    ;;
                  clean)
                    _arguments '1:directory:_directories'
                    return 0
                    ;;
                  cache)
                    case $CURRENT in
                      2)
                        local -a targets
                        targets=(
                          ${hmSpec.renderSubZsh "                " "cache"}
                        )
                        _describe -t cache-targets 'cache target' targets
                        ;;
                    esac
                    return 0
                    ;;
                  *)
                    shift words
                    (( CURRENT-- ))
                    _command_names -e
                    ;;
                esac
                ;;
            esac

            return 1
          }

          _hm "$@"
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
        ${lib.optionalString config.features.development ''
          ${lib.getExe' pkgs.xilo "xilo"} completion zsh > $dir/_xilo
        ''}
        ${lib.optionalString config.features.php ''
          ${pkgs.frankenphp}/bin/frankenphp completion zsh \
            | sed 's/caddy/frankenphp/g' > $dir/_frankenphp
        ''}
      '';

      # Interpolated into both the .zshrc and the zcompdump builder, so runtime
      # and dump-build fpath cannot diverge.
      fpathLine = "fpath=(${
        lib.concatStringsSep " " [
          "${zshConfig}/completions"
          "${zshCompletions}/share/zsh/site-functions"
          "${config.home.path}/share/zsh/site-functions"
        ]
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

      # Frees Tab for fzf-tab. The `zle -N fzf-cd-widget` line has to stay or
      # the `if` block fzf wraps these in is left empty.
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

      # Hook-activated shells run muted: --no-tui skips the TUI (status line,
      # task-log preview), --quiet silences what logs remain, --no-reload
      # drops the PTY watcher whose "devenv watching" line would otherwise
      # ride along. The task lifecycle lines go too: the devenv-quiet overlay
      # (modules/core/overlays.nix) patches --quiet to cover them. Manual
      # `devenv shell` keeps full TUI and output.
      devenvInit = mkInit "devenv" ''
        HOME=$TMPDIR ${lib.getExe pkgs.devenv} hook zsh -- --no-tui --no-reload --quiet > $out/init.zsh
        HOME=$TMPDIR COMPLETE=zsh ${lib.getExe pkgs.devenv} -- >> $out/init.zsh
        cat >> $out/init.zsh <<'EOF'

        # devenv trusts exact paths, so every worktree of an allowed repo
        # would need its own `devenv allow`. A worktree's .git file names the
        # main checkout, so its trust is inherited: when the main checkout is
        # in the DB, an entry for the worktree is appended here. Registered
        # ahead of devenv's own precmd hook, which re-reads the DB every
        # prompt and picks the entry up same-prompt.
        _stubbe_devenv_trust() {
          local dir="''${PWD:a}"
          while [[ ! -f "$dir/devenv.nix" ]]; do
            [[ "$dir" == / ]] && return 0
            dir="''${dir:h}"
          done
          local db="''${XDG_DATA_HOME:-$HOME/.local/share}/devenv/allowed"
          [[ -s "$db" ]] && grep -qF "\"path\":\"$dir\"" "$db" && return 0
          [[ -f "$dir/.git" ]] || return 0
          local gitdir
          gitdir="$(<"$dir/.git")"
          [[ "$gitdir" == gitdir:\ * ]] || return 0
          gitdir="''${gitdir#gitdir: }"
          [[ "$gitdir" == /* ]] || gitdir="$dir/$gitdir"
          gitdir="''${gitdir:a}"
          local main
          if [[ "$gitdir" == */.git/worktrees/* ]]; then
            main="''${gitdir%%/.git/worktrees/*}"
          elif [[ "$gitdir" == */worktrees/* ]]; then
            main="''${gitdir%%/worktrees/*}"
          else
            return 0
          fi
          [[ -s "$db" ]] && grep -qF "\"path\":\"$main\"" "$db" || return 0
          mkdir -p -- "''${db:h}"
          printf '{"path":"%s"}\n' "$dir" >>! "$db"
        }
        if (( ! ''${precmd_functions[(I)_stubbe_devenv_trust]} )); then
          precmd_functions=(_stubbe_devenv_trust $precmd_functions)
        fi
        EOF
      '';

      # -u because the sandbox build user fails compaudit's ownership check,
      # which is irrelevant at runtime.
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
      # Terminals and tmux spawn $SHELL. Pointing it at the nix zsh skips the
      # distro-zsh hop through the .zshenv exec below; logins via passwd
      # (TTY, ssh) still take that hop.
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
          path = "${config.home.homeDirectory}/.zsh_history";
          size = 10000;
          save = 10000;
          extended = true;
          share = true;
          append = true;
          ignoreAllDups = true;
        };
        initContent = lib.mkMerge [
          (lib.mkOrder 500 ''
            source ${zshConfig}/apaths
            source ${zshConfig}/sysfuncs
            source ${zshConfig}/funcs
            ${fpathLine}
          '')
          # fzf-tab must load right after compinit and patina last, so its ZLE
          # hooks wrap the final widget set.
          (lib.mkOrder 1000 ''
            source ${zshConfig}/aliases
            ${sourcePlugins}
            source ${zshConfig}/settings
            (( $+commands[fzf] ))      && source ${fzfInit}
            (( $+commands[starship] )) && source ${starshipInit}
            (( $+commands[zoxide] ))   && source ${zoxideInit}
            (( $+commands[devenv] ))   && source ${devenvInit}
            _patina_init="${config.xdg.cacheHome}/zsh/patina-init.zsh"
            [[ -f "$_patina_init" ]] && source "$_patina_init"
            unset _patina_init
          '')
        ];
      };

      home.file = {
        ".prettierrc.json".source = pkgs.stubbe.gen.json "prettierrc.json" {
          printWidth = 80;
          useTabs = true;
          singleQuote = true;
          overrides = [
            {
              files = [
                "*.md"
                "*.mdx"
              ];
              options = {
                proseWrap = "always";
                printWidth = 80;
              };
            }
          ];
        };
      };

      stubbe.setup.zshPatina.script = ''
        export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        _patina_cache='${config.xdg.cacheHome}/zsh'
        mkdir -p "$_patina_cache"
        if ${lib.getExe pkgs.zsh-patina} activate > "$_patina_cache/patina-init.zsh.tmp" 2>/dev/null; then
          mv "$_patina_cache/patina-init.zsh.tmp" "$_patina_cache/patina-init.zsh"
          ${lib.getExe pkgs.zsh} -c 'zcompile "$1"' _ "$_patina_cache/patina-init.zsh" || true
        else
          rm -f "$_patina_cache/patina-init.zsh.tmp"
        fi
        unset _patina_cache
      '';

      # The hook script is generated at switch time, not built: `zsh-patina
      # activate` embeds $XDG_RUNTIME_DIR and starts the daemon. That generated
      # script never starts the daemon itself, so without this unit highlighting
      # silently does nothing after a reboot.
      systemd.user = {
        services.zsh-patina = {
          Unit.Description = "zsh-patina syntax highlighting daemon";
          Service = {
            ExecStart = "${lib.getExe pkgs.zsh-patina} start --no-daemon";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "default.target" ];
        };

        services.zsh-avahi-hosts = {
          Unit.Description = "Refresh avahi .local host cache for zsh completion";
          Service = {
            Type = "oneshot";
            ExecStart =
              let
                cacheFile = "${config.xdg.cacheHome}/zsh-avahi-hosts";
              in
              pkgs.stubbe.shellScript "zsh-avahi-hosts-refresh" ''
                set -u
                mkdir -p "$(dirname '${cacheFile}')"
                tmp='${cacheFile}.tmp'
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
            OnBootSec = "30s";
            OnUnitActiveSec = "10min";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
