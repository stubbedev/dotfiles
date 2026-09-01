# The tmux/fzf pickers every session binding dispatches to.
_: {
  # Exposed via `stubbe.lib` so the tmux-session check and the installed bins
  # are built from the same bytes.
  stubbe.lib.tmuxLaunchers = {
    "tmux-pick-session" = ''


      DATA_DIR="''${LAZY_TMUX_DATA_DIR:-$HOME/.local/share/lazy-tmux}"
      SELF=''${0:A}

      typeset -A SNAPSHOT_PATH
      snapshot_paths() {
        [[ -d $DATA_DIR/sessions ]] || return 0
        command -v jq >/dev/null 2>&1 || return 0
        jq -r '[.session_name, ([.windows[].panes[].current_path] | first // "")] | @tsv' \
          "$DATA_DIR"/sessions/*.json 2>/dev/null
      }

      label_of() {
        local name="$1" user="''${USER:-$(whoami)}"
        if [[ $name == "$user("*")" ]]; then
          name=''${name#"$user("}
          name=''${name%")"}
        fi
        print -r -- "$name"
      }

      picker_lines() {
        local live name ts size cwd
        live=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)

        while IFS= read -r name; do
          [[ -n $name ]] && printf '%s\t  %s\n' "$name" "$(label_of "$name")"
        done <<< "$live"

        command -v lazy-tmux >/dev/null 2>&1 || return 0

        SNAPSHOT_PATH=()
        while IFS=$'\t' read -r name cwd; do
          [[ -n $name ]] && SNAPSHOT_PATH[$name]="$cwd"
        done < <(snapshot_paths)

        while IFS=$'\t' read -r name ts size; do
          [[ -n $name ]] || continue
          grep -qxF "$name" <<< "$live" && continue
          cwd="''${SNAPSHOT_PATH[$name]}"
          [[ -n $cwd && ! -d $cwd ]] && continue
          printf '%s\t󰒲 %-28s %s  %s\n' \
            "$name" "$(label_of "$name")" "$size" "''${''${ts:0:16}/T/ }"
        done < <(lazy-tmux list 2>/dev/null)
      }

      if [[ $1 == --lines ]]; then
        picker_lines
        exit 0
      fi

      LINES_OUT=$(picker_lines)

      if [[ -z $LINES_OUT ]]; then
        clear
        exit 0
      fi

      SELECTED=$(print -r -- "$LINES_OUT" |
        fzf --prompt="select tmux session: " --delimiter=$'\t' --with-nth=2.. \
          --header='ctrl-x: forget snapshot   tab: copy name' \
          --bind "ctrl-x:execute-silent(lazy-tmux forget --session {1} 2>/dev/null)+reload($SELF --lines)")

      SESSION=''${SELECTED%%$'\t'*}
      [[ -z $SESSION ]] && exit 0

      if ! tmux has-session -t="$SESSION" 2>/dev/null; then
        lazy-tmux wakeup --session "$SESSION" >/dev/null 2>&1 || exit 1
      fi

      if [[ -n $TMUX ]]; then
        tmux switch-client -t "=$SESSION"
      else
        tmux attach-session -t "=$SESSION"
      fi
    '';
    "tmux-pick-project" = ''

      SELECTED=$(fzf-pick-project "$*")

      if [[ -z $SELECTED ]]; then
        exit 0
      fi

      SELECTED_NAME=$(basename "$SELECTED" | tr '.' '_')
      TMUXCLIENTNAME="$(whoami)($SELECTED_NAME)"

      # A snapshot with no pane left under $SELECTED is poisoned: the session
      # was rooted in a worktree that has since been deleted, tmux fell back to
      # its own cwd ($HOME), and the next periodic save froze that. Waking it
      # would reopen the project in $HOME forever, so start fresh instead.
      snapshot_is_stale() {
        local snap paths p
        snap="''${LAZY_TMUX_DATA_DIR:-$HOME/.local/share/lazy-tmux}/sessions/$TMUXCLIENTNAME.json"
        [[ -f $snap ]] || return 1
        command -v jq >/dev/null 2>&1 || return 1
        paths=$(jq -r '.windows[].panes[].current_path // empty' "$snap" 2>/dev/null)
        [[ -n $paths ]] || return 1
        while IFS= read -r p; do
          [[ $p == "$SELECTED"* ]] && return 1
        done <<< "$paths"
        return 0
      }

      # An idle shell whose directory is gone (deleted worktree) poisons every
      # later `new-window -c "#{pane_current_path}"`: tmux cannot chdir there
      # and falls back to its own cwd, which is how a project session ends up
      # opening windows in $HOME. Nothing is running in such a pane, so restart
      # it at the project root instead of inheriting the drift.
      reroot_dead_panes() {
        local pane cwd cmd shell
        shell=$(basename "$(tmux show-option -gv default-shell)")
        while IFS=$'\t' read -r pane cwd cmd; do
          [[ -n $pane && $cmd == "$shell" && ! -d $cwd ]] || continue
          tmux respawn-pane -k -c "$SELECTED" -t "$pane"
        done < <(tmux list-panes -s -t "=$TMUXCLIENTNAME" \
          -F $'#{pane_id}\t#{pane_current_path}\t#{pane_current_command}' 2>/dev/null)
      }

      if command -v direnv >/dev/null 2>&1; then
        if [[ -f "$SELECTED/.envrc" ]] \
            && grep -qxFe 'dotenv_if_exists' -e 'dotenv' "$SELECTED/.envrc"; then
          (
            if grep -qxF 'dotenv_if_exists' "$SELECTED/.envrc" \
                && ! grep -qxF 'dotenv' "$SELECTED/.envrc"; then
              direnv allow "$SELECTED" >/dev/null 2>&1
            else
              zsh -ic "cd ''${(q)SELECTED} && denv on" >/dev/null 2>&1
            fi
          ) &!
        fi
      fi
      if ! tmux has-session -t="$TMUXCLIENTNAME" 2>/dev/null; then
        if snapshot_is_stale ||
            ! lazy-tmux wakeup --session "$TMUXCLIENTNAME" >/dev/null 2>&1; then
          tmux new-session -ds "$TMUXCLIENTNAME" -c "$SELECTED"
          tmux set-option -t "$TMUXCLIENTNAME" @stubbe_has_git 1
        fi
      fi

      reroot_dead_panes

      # attach-session refuses to run inside a client ("sessions should be
      # nested with care"), so the two cases stay split.
      if [[ -n $TMUX ]]; then
        tmux switch-client -t "=$TMUXCLIENTNAME"
      else
        tmux attach-session -t "=$TMUXCLIENTNAME"
      fi
    '';
    "tmux-new-session" = ''

      if [ -z "$1" ]; then
        TMUXCLIENTNAME="$(whoami)(''${''${PWD:t}//./_})"
      else
        TMUXCLIENTNAME="$1"
      fi
      if ! tmux has-session -t="$TMUXCLIENTNAME" 2>/dev/null; then
        lazy-tmux wakeup --session "$TMUXCLIENTNAME" >/dev/null 2>&1
      fi

      tmux new -As "$TMUXCLIENTNAME"
    '';
  };

  flake.modules.homeManager.script-launchers =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      launchers = pkgs.stubbe.tmuxLaunchers // {
        "fzf-pick-directory" = ''

          SELECTED_DIR="$(find . -maxdepth 5 -mindepth 1 -type d ! -path '*/\.*' -print 2>/dev/null | fzf --no-multi --algo=v1 --query="$*")"
          echo "''${SELECTED_DIR:-}"
        '';
        "fzf-pick-project" = ''

          INITIAL_QUERY="$*"
          FILTER_PATTERNS=(
            "go/pkg"
          )
          AWK_FILTER=""
          for pattern in "''${FILTER_PATTERNS[@]}"; do
            ESCAPED_PATTERN="''${pattern//\\/\\\\}"
            ESCAPED_PATTERN="''${ESCAPED_PATTERN//\"/\\\"}"
            if [[ -n "$AWK_FILTER" ]]; then
              AWK_FILTER="$AWK_FILTER && "
            fi
            AWK_FILTER="$AWK_FILTER index(tolower(\$0), tolower(\"$ESCAPED_PATTERN\")) == 0"
          done

          home_results() {
            fd . \
              --base-directory ~ \
              -t d \
              --max-depth 5 \
              --min-depth 1 \
              --hidden 2>/dev/null \
              | awk -v home="$HOME" '!/^\./ && /\/\.git/ { sub(/\/\.git.*/, ""); if (!seen[$0]++) print home "/" $0 }'
          }

          nixos_results() {
            [[ -d /etc/nixos ]] || return 0
            fd . \
              --base-directory /etc/nixos \
              -t d \
              --max-depth 3 \
              --min-depth 1 \
              --hidden 2>/dev/null \
              | awk '/\/\.git/ { sub(/\/\.git.*/, ""); if (!seen[$0]++) print "/etc/nixos/" $0 }'
            [[ -d /etc/nixos/.git ]] && echo "/etc/nixos"
          }

          all_results() {
            home_results
            nixos_results
          }

          if [[ -n "$AWK_FILTER" ]]; then
            SELECTED_PATH="$(all_results | awk "$AWK_FILTER" | fzf --no-multi --query="$INITIAL_QUERY")"
          else
            SELECTED_PATH="$(all_results | fzf --no-multi --query="$INITIAL_QUERY")"
          fi

          echo "''${SELECTED_PATH:-}"
        '';
        "tmux-claude" = ''

          if ! command -v claude &>/dev/null; then
            exit 0
          fi

          inline=0
          if [[ "$1" == "--inline" ]]; then
            inline=1
            shift
          fi

          if [[ -z "$TMUX" || $inline -eq 1 ]]; then
            claude --dangerously-skip-permissions "$@"
          else
            tmux renamew "claude"
            exec claude --dangerously-skip-permissions "$@"
          fi
        '';
        "tmux-lazy-docker" = ''

          if ! command -v lazydocker &>/dev/null; then
            exit 0
          fi

          exec lazydocker
        '';
        "tmux-lazy-git" = ''

          if [[ ! -d .git ]] && ! git rev-parse --git-dir >/dev/null 2>&1; then
            clear
            exit 0
          fi

          if command -v lazygit &>/dev/null; then
            bin=lazygit
          elif command -v bit &>/dev/null; then
            bin=bit
          else
            exit 0
          fi

          exec "$bin"
        '';
        "tmux-pick-directory" = ''

          if [[ $# -eq 1 ]]; then
            SELECTED=$1
          else
            SELECTED=$(find . -maxdepth 5 -mindepth 1 -type d ! -path '*/\.*' -print 2>/dev/null | fzf --algo=v1)
          fi

          if [[ -z $SELECTED ]]; then
            exit 0
          fi

          cd "$SELECTED" || exit 1
        '';
        "tmux-system-monitor" = ''

          if command -v btop &>/dev/null; then
            monitor=btop
          elif command -v htop &>/dev/null; then
            monitor=htop
          else
            exit 0
          fi

          exec "$monitor"
        '';
      };

      launcherBins = lib.mapAttrsToList (name: text: pkgs.stubbe.zshApp { inherit name text; }) launchers;
    in
    {
      home.packages = lib.optionals config.features.desktop launcherBins;
    };
}
