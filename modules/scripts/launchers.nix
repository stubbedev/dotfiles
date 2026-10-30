_: {
  flake.modules.homeManager.script-launchers =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      launchers = {
        "tmux-pick-session" = ''
          label_of() {
            local name="$1" user="''${USER:-$(whoami)}"
            if [[ $name == "$user("*")" ]]; then
            name=''${name#"$user("}
            name=''${name%")"}
            fi
            print -r -- "$name"
          }

          picker_lines() {
            local name
            while IFS= read -r name; do
            [[ -n $name ]] && printf '%s\t%s\n' "$name" "$(label_of "$name")"
            done < <(tmux list-sessions -F "#{session_name}" 2>/dev/null)
          }

          LINES_OUT=$(picker_lines)

          if [[ -z $LINES_OUT ]]; then
            clear
            exit 0
          fi

          SELECTED=$(print -r -- "$LINES_OUT" |
            fzf --prompt="select tmux session: " --delimiter=$'\t' --with-nth=2.. \
              --header='tab: copy name')

          SESSION=''${SELECTED%%$'\t'*}
          [[ -z $SESSION ]] && exit 0

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

          if ! tmux has-session -t="$TMUXCLIENTNAME" 2>/dev/null; then
            tmux new-session -ds "$TMUXCLIENTNAME" -c "$SELECTED"
            tmux set-option -t "$TMUXCLIENTNAME" @stubbe_has_git 1
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
          tmux new -As "$TMUXCLIENTNAME"
        '';
        "fzf-pick-directory" = ''
          SELECTED_DIR="$(find . -maxdepth 5 -mindepth 1 -type d ! -path '*/\.*' -print 2>/dev/null | fzf --no-multi --algo=v1 --query="$*")"
          echo "$SELECTED_DIR"
        '';
        "fzf-pick-project" = ''
          home_results() {
            fd . \
              --base-directory ~ \
              -t d \
              --max-depth 5 \
              --min-depth 1 \
              --hidden 2>/dev/null \
              | awk -v home="$HOME" '!/^\./ && /\/\.git/ { sub(/\/\.git.*/, ""); if (!seen[$0]++) print home "/" $0 }'
          }

          all_results() {
            home_results
            ${lib.optionalString (config.host.platform == "nixos") ''
              fd . \
                --base-directory /etc/nixos \
                -t d \
                --max-depth 3 \
                --min-depth 1 \
                --hidden 2>/dev/null \
                | awk '/\/\.git/ { sub(/\/\.git.*/, ""); if (!seen[$0]++) print "/etc/nixos/" $0 }'
              [[ -d /etc/nixos/.git ]] && echo "/etc/nixos"
            ''}
          }

          SELECTED_PATH="$(all_results | awk '!index(tolower($0), "go/pkg")' | fzf --no-multi --query="$*")"
          echo "$SELECTED_PATH"
        '';
        "tmux-claude" = ''
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
        "tmux-harness" = ''
          if [[ -z "$TMUX" ]]; then
            harness "$@"
          else
            tmux renamew "harness"
            exec harness "$@"
          fi
        '';
        "tmux-lazy-docker" = ''
          exec lazydocker
        '';
        "tmux-lazy-git" = ''
          if ! git rev-parse --git-dir >/dev/null 2>&1; then
            clear
            exit 0
          fi

          exec lazygit
        '';
        "tmux-pick-directory" = ''
          SELECTED=$(fzf-pick-directory "$@")
          if [[ -z $SELECTED ]]; then
            exit 0
          fi

          cd "$SELECTED" || exit 1
          exec "$SHELL"
        '';
        "tmux-system-monitor" = ''
          exec btop
        '';
      };

      toolFeature = {
        "tmux-claude" = config.features.claudeCode;
        "tmux-harness" = config.features.harness;
        "tmux-lazy-docker" = config.features.docker;
        "tmux-system-monitor" = config.features.desktop;
      };

      wanted = lib.filterAttrs (name: _: toolFeature.${name} or true) launchers;
    in
    {
      options.stubbe.launchers = lib.mkOption {
        type = lib.types.attrsOf lib.types.package;
        readOnly = true;
        description = "The launcher bins this host installs, by name, for the bindings that dispatch to them.";
      };

      config = {
        stubbe.launchers = lib.mapAttrs (name: text: pkgs.stubbe.zshApp { inherit name text; }) wanted;
        home.packages = builtins.attrValues config.stubbe.launchers;
      };
    };
}
