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

      # The zsh config tree, inline. Values are the sourceable files; the
      # completions/ subdir goes on fpath. zcompiled below.
      zshFiles = {
        "paths" = ''
          # PATH initialisation for interactive zsh.
          #
          # home-manager already exports the canonical PATH via home.sessionPath
          # (see modules/core/home.nix). This file just guarantees the order is
          # right when zsh starts from contexts that bypass the profile (e.g. tmux
          # panes attaching across reboots) and adds the few dirs Nix doesn't own.
          #
          # The list is deliberately minimal — every CLI tool we use is installed
          # via Nix and reached through home-manager's profile dir (~/.nix-profile
          # on standalone HM, /etc/profiles/per-user/$USER on NixOS-integrated HM).
          # The non-existent candidate is silently skipped by the `[[ -d ]]` guard.
          # Tool-managed install dirs (~/.cargo/bin, ~/.bun/bin, ~/.go/bin,
          # ~/.deno/bin, ~/.opencode/bin, ~/.local/share/nvim/mason/bin, …) stay
          # off PATH so we don't shadow the pinned versions.

          function _paths_init {
            local -a STUBBE_PATHS=(
              "$HOME/.nix-profile/bin"
              "/etc/profiles/per-user/$USER/bin"
              "$HOME/.local/bin"
              "$HOME/.config/composer/vendor/bin"  # PHP composer global
              "$HOME/.local/share/pnpm"             # pnpm global (PNPM_HOME)
              "/sbin"
            )
            local p
            local -a new_paths=()
            for p in "''${STUBBE_PATHS[@]}"; do
              [[ -d "$p" ]] || continue
              [[ ":$PATH:" == *":$p:"* ]] && continue
              new_paths+=("$p")
            done
            (( ''${#new_paths} )) && PATH="''${(j/:/)new_paths}:$PATH"
            export PATH
          }
          _paths_init
          unfunction _paths_init
        '';
        "apaths" = ''
          # EXPAND LIST WITH DESIRED APPLICATION PATHS

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

          # Reload the shell. Re-sourcing ~/.zshrc into the live shell accumulates
          # state — plugins such as fast-syntax-highlighting and zsh-autosuggestions
          # wrap ZLE widgets, so each re-source stacks another wrapper layer and the
          # shell gets slower every reload. `exec` replaces the process with a fresh
          # one instead: a clean reload, no accumulation. cwd and exported env carry
          # over; non-exported vars and the job table do not.
          function src_zsh {
            exec zsh
          }
        '';
        "funcs" = ''
          # shellcheck disable=SC1091

          # Git + worktree workflow now lives in the `treeman` binary as
          # `treeman git <verb>` and `treeman worktree <verb>` subcommands (native
          # TUI pickers, shell completions, tests). What used to be ~1200 lines of
          # zsh here is now thin aliases over those subcommands, plus `cd` shims
          # for the handful of commands that must move the parent shell — a binary
          # can't change its caller's directory, so those print a path and the
          # shim cd's to it.

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

          # Minimal git helpers — only what the `claude` wrapper below needs to
          # decide whether to auto-clean the worktree on exit. Everything else
          # that used to live here moved into treeman.
          function in_git_repo {
            local dir=$PWD
            while [[ $dir != / ]]; do
              [[ -e $dir/.git ]] && { _git_root=$dir; return 0; }
              dir=''${dir:h}
            done
            return 1
          }

          # In a linked worktree, $_git_root/.git is a gitlink file; in the main
          # repo it's a directory. Requires in_git_repo to have run.
          function _in_linked_worktree {
            [[ -f "$_git_root/.git" ]]
          }

          if are_binary git treeman; then
            # Pure-git verbs — direct passthrough, no shell state needed.
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

            # Branch diffs: bare form opens the branch picker; an arg diffs vs it.
            gd()  { treeman git diff --pick "$@"; }
            gcd() { treeman git diff --pick --patch "$@"; }

            # cd-barrier commands: treeman prints the destination path on stdout
            # (status on stderr); the shim cd's the shell there.
            gcb() { local p; p=$(treeman git switch "$@") && [[ -n $p ]] && cd "$p"; }

            gwt() {
              # `gwt -` toggles to the previously-visited worktree.
              if [[ $1 == - ]]; then
                local p; p=$(treeman worktree prev) && [[ -n $p ]] && cd "$p"
                return
              fi
              local p; p=$(treeman worktree switch "$@") && [[ -n $p ]] && cd "$p"
            }

            gwtd() { treeman worktree delete "$@"; }

            # `worktree back` prints the main repo path on line 1 (status follows
            # on later lines); take just the first line to cd.
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

          if is_binary direnv; then
            # Toggle direnv for the current directory.
            #   denv on     write .envrc (defaults to `dotenv`) and allow it
            #   denv off    revoke and delete a .envrc that we created
            #   denv status print direnv status for the current directory
            function denv {
              # Use dotenv_if_exists (not plain `dotenv`) so direnv stays silent
              # when a project has no .env yet — plain `dotenv` calls log_error,
              # which prints to stderr regardless of DIRENV_LOG_FORMAT.
              local marker='dotenv_if_exists'
              local action="''${1:-status}"
              case "$action" in
                on)
                  # Build the desired set of .envrc lines from what's already
                  # there, dropping any bare `dotenv` line (legacy / stray) so it
                  # doesn't fire log_error when .env is absent. Then ensure
                  # `dotenv_if_exists` is present. Any non-dotenv user-authored
                  # lines are preserved verbatim so a hand-written .envrc isn't
                  # clobbered.
                  local _content=""
                  if [[ -f .envrc ]]; then
                    _content="$(grep -vxF 'dotenv' .envrc || true)"
                  fi
                  if ! print -r -- "$_content" | grep -qxF "$marker"; then
                    if [[ -n "$_content" ]]; then
                      _content="''${_content}"$'\n'"$marker"
                    else
                      _content="$marker"
                    fi
                  fi
                  print -r -- "$_content" > .envrc
                  direnv allow
                  ;;
                off)
                  direnv revoke 2>/dev/null
                  if [[ -f .envrc ]]; then
                    # Strip the marker lines we author (current + legacy). If
                    # anything else remains, keep the file with the stripped
                    # contents; otherwise remove it.
                    local _remaining
                    _remaining=$(grep -vxF -e "$marker" -e 'dotenv' .envrc || true)
                    if [[ -z "$_remaining" ]]; then
                      rm -f .envrc
                      echo "denv: removed .envrc"
                    else
                      print -r -- "$_remaining" > .envrc
                      echo "denv: stripped marker from .envrc (kept custom content)"
                    fi
                  fi
                  ;;
                status)
                  direnv status
                  ;;
                *)
                  echo "denv: unknown action '$action' (use: on|off|status)" >&2
                  return 1
                  ;;
              esac
            }
          fi
        '';
        "aliases" = ''
          # INFO: Default Aliases
          alias la='ls -laF'
          alias ff='find . -type f -name'
          alias h='history'
          alias p='ps -f'
          alias sortnr='sort -n -r'
          alias rm='rm -i'
          alias cp='cp -i'
          alias mv='mv -i'

          # INFO: Conditional Aliases
          if is_binary xclip; then
            alias pbcopy='xclip -selection clipboard'
            alias pbpaste='xclip -selection clipboard -o'
          fi

          if is_binary gzip; then
            alias gzcat='gzip -dc'
          fi

          if is_binary nvim; then
            # vi/vim/nano/ed/code come from the nix-wrapper-modules wrapper aliases —
            # see modules/nvim.nix.
            # svim still needs a real alias because it passes -u NONE.
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

            # Bind a key to run a command. Commands that exec, attach, or take over
            # the terminal (exec zsh, tmux attach, nvim) misbehave — or kill the
            # shell — when run from inside a ZLE widget, so the command is deferred
            # to a one-shot precmd hook that fires once ZLE has exited. accept-line
            # on an empty buffer drives that prompt cycle without echoing any text.
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

            # Reload — re-source tmux (when inside it) and exec a fresh zsh. Bound on
            # both Alt-r and Alt-R; inside tmux these are handled by tmux itself.
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

            # disable sort when completing `git checkout`
            zstyle ':completion:*:git-checkout:*' sort false
            # set descriptions format to enable group support
            zstyle ':completion:*:descriptions' format '[%d]'
            # set list-colors to enable filename colorizing
            zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
            # force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
            zstyle ':completion:*' menu no
            if is_binary eza; then
                zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
            fi
            zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept --height=40% --reverse --info=inline
            zstyle ':fzf-tab:*' switch-group '<' '>'
            zstyle ':fzf-tab:*' fuzzy-search true

            # Add avahi-discovered .local hosts to ssh-style completion. The cache
            # file is maintained by the zsh-avahi-hosts systemd user timer
            # (modules/network.nix) — completion only reads it, so it
            # never blocks and never forks.
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
            # ESC→NORMAL and prefix-key disambiguation wait this long (×10ms). zsh
            # default is 40 (400ms) — the source of vi-mode's "laggy" feel. 1 = 10ms,
            # instant mode switch. Read live by ZLE per keystroke, so setting it here
            # (after the plugin loads) takes effect immediately.
            KEYTIMEOUT=1
            ARTISAN_OPEN_ON_MAKE_EDITOR=nvim
            # zsh-autosuggestions perf. Default re-binds every ZLE widget on each
            # precmd ("a decent performance hit" per the plugin) — every plugin here
            # loads before the first prompt, so one rebind captures them all.
            ZSH_AUTOSUGGEST_MANUAL_REBIND=1
            # Don't run the history search on long lines/pastes.
            ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
            # History options live in programs.zsh.history (modules/shell.nix).

            setopt COMPLETE_ALIASES

            _bind_run "^[A" "tmux-lazy-docker"
            _bind_run "^[t" "tmux-new-session"
            _bind_run "^[g" "tmux-lazy-git"
            _bind_run "^[a" "tmux-system-monitor"
            _bind_run "^[h" "tmux-claude"
            _bind_run "^[H" "tmux-claude --inline"

            if is_binary fzf; then
                _bind_run "^[f" "tmux-pick-project"
                _bind_run "^[F" "fzf-project-picker"
                _bind_run "^[d" "tmux-pick-session"
                _bind_run "^[D" "fzf-directory-picker"
            fi
            # fzf/starship/direnv/zoxide init scripts are built at nix build time
            # (modules/shell.nix) and sourced from the store by the
            # generated .zshrc (modules/shell.nix) — nothing to eval here.

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
        "completions/_denv" = ''
          #compdef denv

          _denv() {
            local -a actions
            actions=(
              'on:write .envrc (dotenv) and allow it'
              'off:revoke and delete .envrc if we created it'
              'status:show direnv status for current directory'
            )
            _describe -t actions 'denv action' actions
          }

          _denv "$@"
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
                # Filter current branch at use time (not cache time) so a `git checkout`
                # without leaving $PWD doesn't show a stale current.
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
                # No positional args — suppress default file completion.
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

            # Mirror is_nixos() in modules/scripts.nix so completion only offers
            # verbs the wrapper will actually accept. /etc/os-release is the canonical
            # systemd-distributed identifier; absent on most non-NixOS hosts but cheap
            # to read, so the grep stays scoped to it.
            local -i _hm_is_nixos=0
            if [[ -r /etc/os-release ]] && grep -q '^ID=nixos' /etc/os-release; then
              _hm_is_nixos=1
            fi

            local -a commands
            commands=(
              # Always available — wrapper-defined or platform-agnostic.
              'upgrade:Update system packages, nix channels, and apply switch'
              'update:Update system packages and nix channels'
              'whoami:Print this machine'\'''s age recipient pubkey for sops'
              'trust:Add an age recipient to .sops.yaml and re-wrap secrets/*'
              'secret:Edit, set, or rotate an encrypted file under secrets/'
              'cache:Wipe cached state (nvim|zsh|locks|all)'
              'clean:Interactive TUI to scan/reclaim disk space (build dirs, caches, core dumps, nix gc)'
              'iso:Build the NixOS installer ISO or burn it to a USB device'
              'search:Search for nix packages'
              'help:Print help message'
              'switch:Build and activate configuration'
              'build:Build configuration into result directory'
              'generations:List system / home-manager generations'
              'rollback:Roll back to the previous generation'
              'gc:nix-collect-garbage (defaults to -d)'
            )

            if (( _hm_is_nixos )); then
              # NixOS-only — these all route through nixos-rebuild and have no
              # standalone home-manager equivalent.
              commands+=(
                'boot:Build and set as next-boot only'
                'test:Activate without making it the default'
                'dry-build:Show what would build, do not fetch/build'
                'dry-activate:Show what activate would do, do not activate'
                'build-vm:Build a VM image of the configuration'
                'build-vm-with-bootloader:Build a VM image including a bootloader'
                'repl:Open a nix repl scoped to the configuration'
              )
            else
              # Standalone home-manager only — the wrapper rejects these on NixOS
              # because the home-manager CLI isn't installed in submodule mode.
              commands+=(
                'edit:Open the home configuration in $VISUAL or $EDITOR'
                'option:Inspect configuration option'
                'init:Initialize a configuration in the given directory'
                'instantiate:Instantiate the configuration and print the resulting derivation'
                'remove-generations:Remove indicated generations'
                'expire-generations:Remove generations older than timestamp'
                'packages:List all packages installed in home-manager-path'
                'news:Show news entries in a pager'
                'uninstall:Remove Home Manager'
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
                  search)
                    _message 'package name to search for'
                    ;;
                  option)
                    _message 'configuration option name'
                    ;;
                  remove-generations)
                    # Get generation IDs
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
                      'build:Build the installer ISO'
                      'path:Build the ISO and print its store path'
                      'devices:List removable/block devices'
                      'burn:Build the ISO and write it to a USB device (requires --yes)'
                      'help:Show nixos-iso help'
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
                  update|upgrade|help|edit|build|instantiate|switch|generations|packages|news|uninstall|whoami|boot|test|dry-build|dry-activate|build-vm|build-vm-with-bootloader|repl|rollback)
                    # These commands don't take meaningful tab-completable arguments here;
                    # extra flags fall through via the default _command_names branch.
                    return 0
                    ;;
                  gc)
                    # nix-collect-garbage flags. -d is the wrapper default but the user
                    # may want to override.
                    _arguments \
                      '-d[Delete old generations of all profiles]' \
                      '--delete-old[Delete old generations of all profiles]' \
                      '--delete-older-than[Delete generations older than DURATION]:duration:' \
                      '--dry-run[Print what would be deleted, do not delete]'
                    return 0
                    ;;
                  trust)
                    # `hm trust <name> <pubkey>` or `hm trust <pubkey>` or stdin pipe.
                    case $CURRENT in
                      2) _message 'machine name (or pubkey alone for auto-name)' ;;
                      3) _message 'age recipient pubkey (age1...)' ;;
                    esac
                    return 0
                    ;;
                  secret)
                    # `hm secret edit|set|rotate <name>`. Complete <name> from existing
                    # entries under secrets/ (one binary blob per file).
                    case $CURRENT in
                      2)
                        local -a actions
                        actions=(
                          'edit:Open secrets/<name> in $EDITOR via sops (binary mode)'
                          'set:Replace secrets/<name> with a new value (prompts on TTY, reads stdin otherwise)'
                          'rotate:Re-roll the data key (recipients unchanged)'
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
                    # `hm cache nvim|zsh|locks|all` — see hm_cache() in modules/scripts.nix.
                    case $CURRENT in
                      2)
                        local -a targets
                        targets=(
                          'nvim:Clear ~/.local/{share,state}/nvim and ~/.cache/nvim'
                          'zsh:Remove legacy pre-nix zsh state (plugins.d, fpaths.d, stale zcompdump/zwc)'
                          'locks:Wipe ~/.local/state/nix/home-manager/*.lock.sum (re-prompts on next switch)'
                          'all:nvim + zsh (does NOT touch locks)'
                        )
                        _describe -t cache-targets 'cache target' targets
                        ;;
                    esac
                    return 0
                    ;;
                  *)
                    # For any unrecognized command, fall back to home-manager completion
                    # by removing the first word and calling home-manager completion
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

      # The inline tree materialised and zcompiled.
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
        ".ideavimrc".text = ''
          " LazyVim key mappings for Jetbrains IDEs.

          " LazyVim default settings
          " https://www.lazyvim.org/configuration/general

          let mapleader=" "
          let maplocalleader="\\"

          " Confirm to save changes before exiting modified buffer
          set formatoptions=jcroqlnt
          " Print line number
          set number
          " Relative line numbers
          set relativenumber
          " Lines of context
          set scrolloff=4
          " Round indent
          set shiftround
          " Columns of context
          set sidescrolloff=8
          " which-key says to set this high, or set notimeout
          set timeoutlen=10000
          set notimeout
          set undolevels=10000
          " Disable line wrap
          set nowrap

          " Neovim settings that differ from Vim
          " https://neovim.io/doc/user/diff.html
          " https://github.com/mikeslattery/nvim-defaults.vim/blob/main/plugin/.vimrc

          set backspace=indent,eol,start
          set formatoptions=tcqj
          set listchars=tab:>\ ,trail:-,nbsp:+
          set shortmess=filnxtToOF

          " Enable plugin behavior

          " https://github.com/JetBrains/ideavim/wiki/IdeaVim-Plugins
          " https://www.lazyvim.org/plugins

          Plug 'kana/vim-textobj-entire'
          Plug 'dbakker/vim-paragraph-motion'
          Plug 'michaeljsmith/vim-indent-object'
          Plug 'machakann/vim-highlightedyank'
          Plug 'vim-scripts/argtextobj.vim'
          " gcc and gc<action> mappings.
          Plug 'tpope/vim-commentary'

          " Emulate LazyVim mini.surround mappings
          Plug 'tpope/vim-surround'
          set g:surround_no_mappings = 1
          nmap gsa <Plug>YSurround
          xmap gsa <Plug>VSurround
          nmap gsr <Plug>CSurround
          nmap gsd <Plug>DSurround

          " Use s to jump anywhere (similar to flash.nvim in LazyVim)
          set easymotion
          set g:EasyMotion_do_mapping = 0
          nmap s <Plug>(easymotion-s)
          xmap s <Plug>(easymotion-s)
          omap s <Plug>(easymotion-s)

          " similar to flash.nvim
          Plug 'justinmk/vim-sneak'
          " Enable the whichkey plugin, available on Jetbrains marketplace
          set which-key
          " Extended matching.  A Neovim default plugin.
          set matchit
          set functiontextobj

          " Key maps

          " https://www.lazyvim.org/configuration/keymaps

          " To track Action-IDs
          " :action VimFindActionIdAction

          " General Keymaps

          " Go to Left Window
          nmap <C-h> <C-w>h
          " Go to Lower Window
          nmap <C-j> <C-w>j
          " Go to Upper Window
          nmap <C-k> <C-w>k
          " Go to Right Window
          nmap <C-l> <C-w>l
          " Increase Window Height
          nmap <C-Up> <Action>(IncrementWindowHeight)
          " Decrease Window Height
          nmap <C-Down> <Action>(DecrementWindowHeight)
          " Decrease Window Width
          nmap <C-Left> <Action>(DecrementWindowWidth)
          " Increase Window Width
          nmap <C-Right> <Action>(IncrementWindowWidth)
          " Move Down
          nmap <A-j> <Action>(MoveLineDown)
          imap <A-j> <Esc><Action>(MoveLineDown)i
          " Move Up
          nmap <A-k> <Action>(MoveLineUp)
          imap <A-k> <Esc><Action>(MoveLineUp)i
          " Prev Buffer
          nmap <S-h> <Action>(PreviousTab)
          " Next Buffer
          nmap <S-l> <Action>(NextTab)
          " Prev Buffer (alternative)
          nmap [b <Action>(PreviousTab)
          " Next Buffer (alternative)
          nmap ]b <Action>(NextTab)
          " Switch to Other Buffer
          nnoremap <leader>bb <C-^>
          " Switch to Other Buffer (alternative)
          nnoremap <leader>` <C-^>
          " Delete Buffer
          nmap <leader>bd <Action>(CloseContent)
          " Delete All Buffers Except Active
          nmap <leader>bD <Action>(CloseAllEditorsButActive)
          " Toggle Pin on Current Tab
          nmap <leader>bp <Action>(PinActiveEditorTab)
          " Close All Unpinned Buffers
          nmap <leader>bP <Action>(CloseAllUnpinnedEditors)
          " Escape and Clear hlsearch
          nnoremap <esc> :nohlsearch<CR>
          nnoremap <leader>ur :nohlsearch<CR>
          " Keywordprg
          nmap <leader>K :help<space><C-r><C-w><CR>
          " Add Comment Below
          nmap gco o<c-o>gcc
          " Add Comment Above
          nmap gcO O<c-o>gcc
          " Lazy
          nmap <leader>l <Action>(WelcomeScreen.Plugins)
          " New File
          nmap <leader>fn <Action>(NewElementSamePlace)
          " Location List
          nmap <leader>xl <Action>(ActivateProblemsViewToolWindow)
          " Quickfix List
          nmap <leader>xq <Action>(ActivateProblemsViewToolWindow)
          " Previous Quickfix
          nmap [q <Action>(GotoPreviousError)
          " Next Quickfix
          nmap ]q <Action>(GotoNextError)
          " Format
          nmap <leader>cf <Action>(Format)
          vmap <leader>cf <Action>(Format)
          " Line Diagnostics
          nmap <leader>cd <Action>(ActivateProblemsViewToolWindow)
          " Next Diagnostic
          nmap ]d <Action>(GotoNextError)
          " Prev Diagnostic
          nmap [d <Action>(GotoPreviousError)
          " Next Error
          nmap ]e <Action>(GotoNextError)
          " Prev Error
          nmap [e <Action>(GotoPreviousError)
          " Next Warning
          nmap ]w <Action>(GotoNextError)
          " Prev Warning
          nmap [w <Action>(GotoPreviousError)
          " Toggle Auto Format (Global)
          nmap <leader>ub :echo 'There is no equivalent mapping for Toggle Auto Format.'<cr>
          " Toggle Auto Format (Buffer)
          nmap <leader>uB :echo 'There is no equivalent mapping for Toggle Auto Format.'<cr>
          " Toggle Spelling
          nmap <leader>us :setlocal spell!<CR>
          " Toggle Wrap
          nmap <leader>uw :setlocal wrap!<CR>
          " Toggle Relative Number
          nmap <leader>uL :set relativenumber!<CR>
          " Toggle Diagnostics
          nmap <leader>ud <Action>(ActivateProblemsViewToolWindow)
          " Toggle Line Numbers
          nmap <leader>ul :set number!<CR>
          " Toggle conceallevel
          nmap <leader>uc :echo 'There is no equivalent mapping for Toggle Conceallevel.'<cr>
          " Toggle Treesitter Highlight
          nmap <leader>uT :echo 'There is no equivalent mapping for Toggle Treesitter Highlight.'<cr>
          " Toggle Background
          nmap <leader>ub <Action>(QuickChangeScheme)
          " Toggle Inlay Hints
          nmap <leader>uh <Action>(ToggleInlayHintsGloballyAction)
          " Lazygit (Root Dir)
          nmap <leader>gg <Action>(ActivateCommitToolWindow)
          " Lazygit (cwd)
          nmap <leader>gG <Action>(ActivateCommitToolWindow)
          " Git Blame Line
          nmap <leader>gb <Action>(Annotate)
          """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
          " Git Browse
          nmap <leader>gB <Action>(Vcs.Show.Log)
          " Lazygit Current File History
          nmap <leader>gf <Action>(Vcs.ShowTabbedFileHistory)
          " Lazygit Log
          nmap <leader>gl <Action>(Vcs.Show.Log)
          " Lazygit Log (cwd)
          nmap <leader>gL <Action>(Vcs.Show.Log)
          " Quit All
          nmap <leader>qq <Action>(Exit)
          " Inspect Pos
          nmap <leader>ui <Action>(ActivateStructureToolWindow)
          " Inspect Tree
          nmap <leader>uI <Action>(ActivateStructureToolWindow)
          " LazyVim Changelog
          nmap <leader>L <Action>(WhatsNewAction)
          " Terminal (Root Dir)
          nmap <leader>ft <Action>(ActivateTerminalToolWindow)
          " Terminal (cwd)
          nmap <leader>fT <Action>(ActivateTerminalToolWindow)
          " Terminal (Root Dir)
          nmap <C-/> <Action>(NewScratchFile)
          nmap <leader>rs <Action>(Scratch.ShowFilesPopup)
          nmap <leader>rr <Action>(RunClass)
          " nmap <C-_> 'There is no equivalent mapping for <c-_>.'<cr>
          " Hide Terminal - terminal mode maps not possible
          " Split Window Below.  :split<cr> doesn't work.
          nmap <leader>- <c-w>s
          " Split Window Right
          nmap <leader><bar> <c-w>v
          " Delete Window
          nmap <leader>wd <Action>(CloseContent)
          " Toggle Maximize
          nmap <leader>wm <Action>(ToggleDistractionFreeMode)
          " Last Tab
          nmap <leader><tab>l <Action>(StoreDefaultLayout)<Action>(ChangeToolWindowLayout)
          " Close Other Tabs
          nmap <leader><tab>o :<cr>
          " First Tab
          nmap <leader><tab>f <Action>(StoreDefaultLayout)<Action>(ChangeToolWindowLayout)
          " New Tab
          nmap <leader><tab>f <Action>(StoreDefaultLayout)<Action>(StoreNewLayout)
          " Next Tab
          nmap <leader><tab>] <Action>(StoreDefaultLayout)<Action>(ChangeToolWindowLayout)
          " Previous Tab
          nmap <leader><tab>[ <Action>(StoreDefaultLayout)<Action>(ChangeToolWindowLayout)
          " Close Tab
          nmap <leader><tab>f <Action>(StoreDefaultLayout)<Action>(ChangeToolWindowLayout)

          " LSP Keymaps

          " Lsp Info
          nmap <leader>cc :echo 'There is no equivalent mapping for Lsp Info.'<cr>
          " Goto Definition
          nmap gd <Action>(GotoDeclaration)
          " References
          nmap gr <Action>(FindUsages)
          " Goto Implementation
          nmap gI <Action>(GotoImplementation)
          " Goto Type Definition
          nmap gy <Action>(GotoTypeDeclaration)
          " Goto Declaration
          nmap gD <Action>(GotoDeclaration)
          " Signature Help
          nmap gK <Action>(ParameterInfo)
          " Signature Help in Insert Mode
          imap <C-k> <C-o><Action>(ParameterInfo)
          " Code Action
          nmap <leader>ca <Action>(RefactoringMenu)
          vmap <leader>ca <Action>(RefactoringMenu)
          " Run Codelens
          nmap <leader>cc :echo 'There is no equivalent mapping for Run Codelens.'<cr>
          vmap <leader>cc :echo 'There is no equivalent mapping for Run Codelens.'<cr>
          " Refresh & Display Codelens
          nmap <leader>cC :echo 'There is no equivalent mapping for Refresh & Display Codelens.'<cr>
          " Rename File
          nmap <leader>cR <Action>(RenameFile)
          " Rename
          nmap <leader>cr <Action>(RenameElement)
          " Source Action
          nmap <leader>cA <Action>(ShowIntentionActions)
          " Next Reference
          nmap ]] <Action>(GotoNextElementUnderCaretUsage)
          " Prev Reference
          nmap [[ <Action>(GotoPrevElementUnderCaretUsage)
          " Next Method
          nmap ]m <Action>(MethodDown)
          " Previous Method
          nmap [m <Action>(MethodUp)
          " Next Reference (alternative)
          nmap <a-n> <Action>(GotoNextElementUnderCaretUsage)
          " Prev Reference (alternative)
          nmap <a-p> <Action>(GotoPrevElementUnderCaretUsage)

          " Bufferline

          " Delete buffers to the left
          nmap <leader>bl <Action>(CloseAllToTheLeft)
          " Toggle pin
          nmap <leader>bp <Action>(PinActiveTabToggle)
          " Delete Non-Pinned Buffers
          nmap <leader>bP <Action>(CloseAllUnpinnedEditors)
          " Delete buffers to the right
          nmap <leader>br <Action>(CloseAllToTheRight)

          " Neo-tree Keymaps

          " Buffer Explorer
          nmap <leader>be <Action>(ActivateProjectToolWindow)
          " Explorer NeoTree (Root Dir)
          nmap <leader>e <Action>(FileStructurePopup)
          " Explorer NeoTree (cwd)
          nmap <leader>E <Action>(SelectInProjectView)
          " Explorer NeoTree (Root Dir) (alternative)
          nmap <leader>fe <Action>(ActivateProjectToolWindow)
          " Explorer NeoTree (cwd) (alternative)
          nmap <leader>fE <Action>(ActivateProjectToolWindow)
          " Git Explorer
          nmap <leader>ge <Action>(ActivateVersionControlToolWindow)

          " Notifications (noice, snacks)

          nmap <leader>snd <Action>(ClearAllNotifications)
          nmap <leader>un <Action>(ClearAllNotifications)

          " Telescope Keymaps

          nmap <leader>pf <Action>(com.mituuz.fuzzier.Fuzzier)
          nmap <leader>mf <Action>(com.mituuz.fuzzier.FuzzyMover)

          " Find Files (Root Dir)
          nmap <leader><space> <Action>(GotoFile)
          " Switch Buffer
          nmap <leader>, <Action>(Switcher)
          " Grep (Root Dir)
          nmap <leader>/ <Action>(FindInPath)
          " Command History
          nmap <leader>: :history<cr>
          " Buffers
          nmap <leader>fb <Action>(Switcher)
          " Find Config File
          nmap <leader>fc <Action>(GotoFile)
          " Find Files (Root Dir) (alternative)
          nmap <leader>ff <Action>(GotoFile)
          " Find Files (cwd)
          nmap <leader>fF <Action>(GotoFile)
          " Find Files (git-files)
          nmap <leader>fg <Action>(GotoFile)
          " Recent
          nmap <leader>fr <Action>(RecentFiles)
          " Recent (cwd)
          nmap <leader>fR <Action>(RecentFiles)
          " Commits
          nmap <leader>gc <Action>(Vcs.Show.Log)
          " Status
          nmap <leader>gs <Action>(Vcs.Show.Log)
          " Registers
          nmap <leader>s" :registers<cr>
          " Auto Commands
          nmap <leader>sa :echo 'There is no equivalent mapping.'<cr>
          " Buffer
          nmap <leader>sb <Action>(Switcher)
          " Command History (alternative)
          nmap <leader>sc :history<cr>
          " Commands
          nmap <leader>sC <Action>(GotoAction)
          " Document Diagnostics
          nmap <leader>sd <Action>(ActivateProblemsViewToolWindow)
          " Workspace Diagnostics
          nmap <leader>sD <Action>(ActivateProblemsViewToolWindow)
          " Grep (Root Dir) (alternative)
          nmap <leader>sg <Action>(FindInPath)
          " Grep (cwd)
          nmap <leader>sG <Action>(FindInPath)
          " Help Pages
          nmap <leader>sh <Action>(HelpTopics)
          " Search Highlight Groups
          nmap <leader>sH <Action>(HighlightUsagesInFile)
          " Jumplist
          nmap <leader>sj <Action>(RecentLocations)
          " Key Maps
          nmap <leader>sk :map<cr>
          " Location List
          nmap <leader>sl <Action>(ActivateProblemsViewToolWindow)
          " Jump to Mark
          nmap <leader>sm :marks<cr>
          " Man Pages
          nmap <leader>sM <Action>(ShowDocumentation)
          " Options
          nmap <leader>so <Action>(ShowSettings)
          " Quickfix List
          nmap <leader>sq <Action>(ActivateProblemsViewToolWindow)
          " Resume
          nmap <leader>sR :echo 'Not yet implmented.'<cr>
          " Goto Symbol
          nmap <leader>ss <Action>(GotoSymbol)
          " Goto Symbol (Workspace)
          nmap <leader>sS <Action>(GotoSymbol)
          " Word (Root Dir)
          nmap <leader>sw mzviw<Action>(FindInPath)<esc>`z
          " Word (cwd)
          nmap <leader>sW mzviw<Action>(FindInPath)<esc>`z
          " Selection (Root Dir)
          vmap <leader>sw <Action>(FindInPath)
          " Selection (cwd)
          vmap <leader>sW <Action>(FindInPath)
          " Colorscheme with Preview
          nmap <leader>uC <Action>(QuickChangeScheme)


          " DAP Keymaps

          " Run with Args
          nmap <leader>da <Action>(ChooseRunConfiguration)
          " Toggle Breakpoint
          nmap <leader>db <Action>(ToggleLineBreakpoint)
          " Breakpoint Condition
          nmap <leader>dB <Action>(AddConditionalBreakpoint)
          " Continue
          nmap <leader>dc <Action>(Resume)
          " Run to Cursor
          nmap <leader>dC <Action>(ForceRunToCursor)
          " Go to Line (No Execute)
          nmap <leader>dg <Action>(GotoLine)
          " Step Into
          nmap <leader>di <Action>(StepInto)
          " Down
          nmap <leader>dj <Action>(GotoNextError)
          " Up
          nmap <leader>dk <Action>(GotoPreviousError)
          " Run Last
          nmap <leader>dl <Action>(Debug)
          " Step Out
          nmap <leader>do <Action>(StepOut)
          " Step Over
          nmap <leader>dO <Action>(StepOver)
          " Pause
          nmap <leader>dp <Action>(Pause)
          " Toggle REPL
          nmap <leader>dr <Action>(JShell.Console)
          " Session
          nmap <leader>ds :echo 'Not yet implmented.'<cr>
          " Terminate
          nmap <leader>dt <Action>(Stop)
          " Widgets
          nmap <leader>dw :echo 'There is no equivalent mapping for Widgets.'<cr>

          " Todo-comments Keymaps

          " Todo
          nmap <leader>st <Action>(ActivateTODOToolWindow)
          " Todo/Fix/Fixme
          nmap <leader>sT <Action>(ActivateTODOToolWindow)
          " Todo (Trouble)
          nmap <leader>xt <Action>(ActivateTODOToolWindow)
          " Todo/Fix/Fixme (Trouble)
          nmap <leader>xT <Action>(ActivateTODOToolWindow)
          " Previous Todo Comment
          nmap [t ?\(TODO\|FIX\|HACK\|WARN\|PERF\|NOTE\|TEST\|INFO\):<cr>
          " Next Todo Comment
          nmap ]t /\(TODO\|FIX\|HACK\|WARN\|PERF\|NOTE\|TEST\|INFO\):<cr>

          " DAP UI Keymaps

          " Eval
          nmap <leader>de <Action>(EvaluateExpression)
          vmap <leader>de <Action>(EvaluateExpression)
          " Dap UI
          nmap <leader>du <Action>(ActivateDebugToolWindow)

          " Neotest Keymaps

          " Run Last
          nmap <leader>tl <Action>(Run)
          " Show Output
          nmap <leader>to <Action>(ActivateRunToolWindow)
          " Toggle Output Panel
          nmap <leader>tO <Action>(ActivateRunToolWindow)
          " Run Nearest
          nmap <leader>tr <Action>(RunClass)
          " Toggle Summary
          nmap <leader>ts :echo 'Not yet implmented.'<cr>
          " Stop
          nmap <leader>tS <Action>(Stop)
          " Run File
          nmap <leader>tt <Action>(RunClass)
          " Run All Test Files
          nmap <leader>tT :echo 'Not yet implmented.'<cr>
          " Toggle Watch
          nmap <leader>tw :echo 'Not yet implmented.'<cr>

          " nvim-dap
          " Debug Nearest
          nmap <leader>td <Action>(ChooseDebugConfiguration)

          " Neovim mappings
          " https://neovim.io/doc/user/vim_diff.html#_default-mappings

          nnoremap Y y$
          inoremap <C-U> <C-G>u<C-U>
          inoremap <C-W> <C-G>u<C-W>
          " Q isn't exactly the same.
          nnoremap Q @@
          " There are several more Neovim mappings that need to be ported.  See link.

          " Macro Keymaps
          set vim-macro
          let g:macro_cycle = "a"

          function! CycleMacroRegister()
            if g:macro_cycle == "a"
              let g:macro_cycle = "b"
            elseif g:macro_cycle == "b"
              let g:macro_cycle = "c"
            else
              let g:macro_cycle = "a"
            endif
            echo "Macro slot: " . g:macro_cycle
          endfunction

          " Start/stop recording in the current macro slot
          nnoremap <silent> q :execute "normal! q" . g:macro_cycle<CR>

          " Replay the macro from the current slot
          nnoremap <silent> Q :execute "normal! @" . g:macro_cycle<CR>

          " Cycle macro slot (Ctrl+q)
          nnoremap <silent> <C-q> :call CycleMacroRegister()<CR>


          " Jetbrains conflicts
          " https://github.com/JetBrains/ideavim/blob/master/doc/sethandler.md
          " None, yet.  Possible conflicts: ctrl -6befhjklorsvw
        '';
        ".prettierrc.json".source = (pkgs.formats.json { }).generate "prettierrc.json" {
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
      # _avahi_ssh_hosts in the settings file above only reads this cache. The
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
