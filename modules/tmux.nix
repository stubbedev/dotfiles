_: {
  flake.modules.homeManager.tmux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      p = pkgs.stubbe.withHash;

      launchers = config.stubbe.launchers;

      toolWindows = lib.filter (w: launchers ? ${w.launcher}) [
        {
          window = "sysmon";
          launcher = "tmux-system-monitor";
          key = "M-a";
        }
        {
          window = "lazydocker";
          launcher = "tmux-lazy-docker";
          key = "M-A";
        }
      ];

      runtimeSubdir = "tmux";
      tmuxTmpdir = "\${XDG_RUNTIME_DIR}/${runtimeSubdir}";

      tmuxServer = pkgs.stubbe.shellScript "tmux-server" ''
        . ${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh
        exec ${lib.getExe config.programs.tmux.package} -D
      '';

      directions =
        map
          (
            d:
            d
            // {
              word = lib.toLower d.key;
              edge = "pane_at_${d.token}";
            }
          )
          [
            {
              key = "Left";
              flag = "L";
              token = "left";
              joinFlags = "-b -h";
              fullDim = "height";
            }
            {
              key = "Right";
              flag = "R";
              token = "right";
              joinFlags = "-h";
              fullDim = "height";
            }
            {
              key = "Up";
              flag = "U";
              token = "top";
              joinFlags = "-b";
              fullDim = "width";
            }
            {
              key = "Down";
              flag = "D";
              token = "bottom";
              joinFlags = "";
              fullDim = "width";
            }
          ];

      # Windows 1-10: Alt+<digit> selects, Alt+Shift+<digit> moves the current
      # pane there. The shifted row is the US-layout shift of each digit, which
      # tmux names literally (`#` and `$` are escaped for tmux's config parser).
      windowKeys =
        lib.imap1
          (n: shift: {
            inherit n shift;
            digit = toString (lib.mod n 10);
          })
          [
            "!"
            "@"
            "\\#"
            "\\$"
            "%"
            "^"
            "&"
            "*"
            "("
            ")"
          ];
    in
    {
      # The command palette every bind and hook in tmux.conf dispatches to.
      home.file.".config/tmux/scripts/commands.sh".source = pkgs.stubbe.shellScript "tmux-commands" ''
        PINNED_STATE="''${XDG_STATE_HOME:-$HOME/.local/state}/tmux/pinned"

        toggle_window() {
          local window_name="$1"
          shift
          local current_window
          local current_path

          current_window=$(tmux display-message -p '#W')
          current_path=$(tmux display-message -p -F "#{pane_current_path}")

          if [ "$current_window" = "$window_name" ]; then
            tmux last-window 2>/dev/null || true
            return 0
          fi

          if tmux select-window -t "=$window_name" 2>/dev/null; then
            if [ "$#" -gt 0 ] &&
              [ "$(tmux display-message -p '#{pane_current_command}')" = "$(basename "$(tmux show-option -gv default-shell)")" ]; then
              tmux respawn-pane -k "$@"
            fi
            return
          fi

          if [ "$#" -eq 0 ]; then
            return
          fi

          tmux new-window -c "$current_path" -n "$window_name" "$@"
        }

        git_flag_of_pane() {
          local current_path
          current_path=$(tmux display-message -p -t "$1" -F "#{pane_current_path}")
          if [ -n "$current_path" ] && git -C "$current_path" rev-parse --git-dir >/dev/null 2>&1; then
            echo 1
          else
            echo 0
          fi
        }

        session_init() {
          local session_name pane_id

          session_name=$(tmux display-message -p -F "#{hook_session_name}")
          if [ -z "$session_name" ]; then
            session_name=$(tmux display-message -p -F "#S")
          fi

          pane_id=$(tmux display-message -p -F "#{hook_pane}")
          if [ -z "$pane_id" ]; then
            pane_id=$(tmux display-message -p -F "#{pane_id}")
          fi

          tmux set-option -q -t "$session_name" @stubbe_has_git "$(git_flag_of_pane "$pane_id")"
        }

        branch_ticket() {
          local path="$1"
          [ -z "$path" ] && return
          local branch
          branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null) || return
          local ticket
          ticket=$(printf '%s' "$branch" | grep -oE '[A-Z]+-[0-9]+' | head -1)
          [ -n "$ticket" ] && printf ' %s' "$ticket"
        }

        set_ssh_flag() {
          local sess="''${1:-$(tmux display-message -p '#S')}"
          local flag=0
          local pid
          while IFS= read -r pid; do
            [ -z "$pid" ] && continue
            if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -q '^SSH_CONNECTION='; then
              flag=1
              break
            fi
          done < <(tmux list-clients -t "$sess" -F '#{client_pid}' 2>/dev/null)
          tmux set-option -q -t "$sess" @stubbe_ssh "$flag"
        }

        refresh_session_git_flag() {
          tmux set-option -q -t "$(tmux display-message -p -F "#S")" @stubbe_has_git \
            "$(git_flag_of_pane "$(tmux display-message -p -F "#{pane_id}")")"
        }

        toggle_lazygit_window() {
          refresh_session_git_flag

          if [ "$(tmux show-option -qv @stubbe_has_git)" != "1" ]; then
            return
          fi

          toggle_window "lazygit" ${lib.getExe launchers.tmux-lazy-git}
        }

        pane_is_pinned() {
          [ "$(tmux show-options -t "$1" -pqv @pinned)" = "1" ]
        }

        toggle_pin() {
          local pane_id
          pane_id=$(tmux display-message -p "#{pane_id}")
          if pane_is_pinned "$pane_id"; then
            tmux set -p -t "$pane_id" @pinned 0
          else
            tmux set -p -t "$pane_id" @pinned 1
          fi
          save_pins
        }

        client_changed() {
          set_ssh_flag "$1"
          restore_pins
        }

        save_pins() {
          mkdir -p "''${PINNED_STATE%/*}"
          # Keyed by pane_id: window/pane indexes shift when windows are
          # killed, and an index-only dump would re-pin the wrong pane on
          # the next restore.
          tmux list-panes -a -F '#{@pinned}	#{session_name}	#{window_index}	#{pane_index}	#{pane_id}' |
            sed -n 's/^1	//p' > "$PINNED_STATE.tmp"
          mv "$PINNED_STATE.tmp" "$PINNED_STATE"
        }

        restore_pins() {
          [ -f "$PINNED_STATE" ] || return 0
          local pane_id
          while IFS=$'\t' read -r _ _ _ pane_id; do
            [ -n "$pane_id" ] || continue
            tmux set -p -t "$pane_id" @pinned 1 2>/dev/null || true
          done < "$PINNED_STATE"
        }

        kill_pane() {
          local pane_id window_id
          pane_id=$(tmux display-message -p "#{pane_id}")
          if ! pane_is_pinned "$pane_id" || [ "$(tmux display-message -p "#{@kill_pane_pending}")" = "1" ]; then
            tmux kill-pane
            return
          fi
          window_id=$(tmux display-message -p "#{window_id}")
          tmux set -p -t "$pane_id" @kill_pane_pending 1
          pending_animation "$pane_id" "$window_id" pane
        }

        kill_window() {
          local window_id
          window_id=$(tmux display-message -p "#{window_id}")
          if ! grep -qx 1 <<<"$(tmux list-panes -t "$window_id" -F "#{@pinned}")" ||
            [ "$(tmux display-message -p "#{@kill_window_pending}")" = "1" ]; then
            tmux kill-window
            return
          fi
          tmux set -w -t "$window_id" @kill_window_pending 1
          pending_animation "$(tmux display-message -p "#{pane_id}")" "$window_id" window
        }

        kill_server_confirm() {
          local pending
          pending=$(tmux show-option -gv @kill_server_pending 2>/dev/null)
          if [ "$pending" = "1" ]; then
            tmux kill-server
            return
          fi

          tmux set -g @kill_server_pending 1
          sleep 1.5
          tmux set -g @kill_server_pending 0 2>/dev/null
        }

        join_direction() {
          local pane_width pane_height
          pane_width=$(tmux display-message -p "#{pane_width}")
          pane_height=$(tmux display-message -p "#{pane_height}")
          if [ "$pane_width" -gt "$((pane_height * 2))" ]; then
            echo -h
          fi
        }

        toggle_mark_join() {
          local pane_marked pane_marked_set

          pane_marked=$(tmux display-message -p "#{pane_marked}")
          if [ "$pane_marked" = "1" ]; then
            tmux select-pane -M
            return
          fi

          pane_marked_set=$(tmux display-message -p "#{pane_marked_set}")
          if [ "$pane_marked_set" != "1" ]; then
            tmux select-pane -m
            return
          fi

          # shellcheck disable=SC2046
          tmux join-pane $(join_direction)
        }

        pending_animation() {
          local pane_id="$1"
          local win_id="$2"
          local scope="$3" # "pane" or "window"
          local duration_us=300000
          local fill_style="#[bg=${p.red},fg=${p.base},bold]"

          local flag_scope flag_target flag_name
          case "$scope" in
          pane)   flag_scope=-p ; flag_target="$pane_id" ; flag_name=@kill_pane_pending ;;
          window) flag_scope=-w ; flag_target="$win_id"  ; flag_name=@kill_window_pending ;;
          esac
          local restore
          printf -v restore 'tmux set -wu -t %q window-status-current-format 2>/dev/null; tmux set %s -t %q %s 0 2>/dev/null' \
            "$win_id" "$flag_scope" "$flag_target" "$flag_name"
          # shellcheck disable=SC2064
          trap "$restore" EXIT INT TERM

          shopt -s extglob
          local raw base_style template
          raw=$(tmux show-options -gqv window-status-current-format)
          [[ "$raw" =~ ^(#\[[^]]*\]) ]] && base_style="''${BASH_REMATCH[1]}"
          template="''${raw//#\[*([^]])\]/}"

          local rest="$template" expanded="" pre job out
          while [[ "$rest" == *'#('* ]]; do
            pre="''${rest%%#(*}"
            rest="''${rest#*#(}"
            job="''${rest%%)*}"
            rest="''${rest#*)}"
            out=$(eval "$(tmux display-message -p -t "$win_id" "$job")" 2>/dev/null)
            expanded+="$pre''${out//%/%%}"
          done
          template="$expanded$rest"

          local rendered
          rendered=$(tmux display-message -p -t "$win_id" "$template")

          local -a chars=()
          while IFS= read -r c; do
            chars+=("$c")
          done < <(LC_ALL=C.UTF-8 grep -o . <<<"$rendered")

          local -a esc=()
          local n
          for n in "''${chars[@]}"; do
            n="''${n//#/##}"
            esc+=("''${n//%/%%}")
          done

          local per_cell total=''${#chars[@]}
          if (( total == 0 )); then
            printf -v per_cell "0.%06d" "$duration_us"
            sleep "$per_cell"
            return
          fi
          printf -v per_cell "0.%06d" "$((duration_us / total))"

          local i j frame style
          for ((i = 1; i <= total; i++)); do
            frame=""
            for ((j = 0; j < total; j++)); do
              ((j < i)) && style="$fill_style" || style="$base_style"
              frame+="''${style}''${esc[$j]}"
            done
            tmux set -wt "$win_id" window-status-current-format "$frame" 2>/dev/null
            sleep "$per_cell"
          done

          sleep 0.2
        }

        reload_animation() {
          local chars=("⡿" "⣟" "⣯" "⣷" "⣾" "⣽" "⣻" "⢿")
          local original restore
          original=$(tmux show-option -gqv status-left)
          printf -v restore 'tmux set -g status-left %q 2>/dev/null' "$original"
          # shellcheck disable=SC2064
          trap "$restore" EXIT INT TERM

          local n=''${#chars[@]}
          local total=$((n * 2))
          local peak=$((n - 1))
          local i t r g b color
          for ((i = 0; i < total; i++)); do
            (( i < n )) && t=$i || t=$((total - 1 - i))
            r=$((243 + 6 * t / peak))
            g=$((139 + 87 * t / peak))
            b=$((168 + 7 * t / peak))
            printf -v color "#%02x%02x%02x" "$r" "$g" "$b"
            tmux set -g status-left "#[bg=default,bold,fg=''${color}] ''${chars[i % n]} "
            sleep 0.08
          done
        }

        reload() {
          if [[ "$(tmux display-message -p '#{pane_current_command}')" == *zsh ]]; then
            tmux send-keys M-R
          else
            tmux source-file "$HOME/.config/tmux/tmux.conf"
          fi
          reload_animation
        }

        move_pane() {
          local direction="$1"
          local pane_id pane_count edge_flag target_token target_pane
          local pane_width pane_height window_width window_height
          local join_flags=()
          pane_id=$(tmux display-message -p "#{pane_id}")
          pane_count=$(tmux display-message -p "#{window_panes}")
          pane_width=$(tmux display-message -p "#{pane_width}")
          pane_height=$(tmux display-message -p "#{pane_height}")
          window_width=$(tmux display-message -p "#{window_width}")
          window_height=$(tmux display-message -p "#{window_height}")

          if [ "$pane_count" -le 1 ]; then
            return
          fi

          case "$direction" in
          ${lib.concatMapStringsSep "\n  " (
            d:
            lib.concatStringsSep "\n    " [
              "${d.flag})"
              ''edge_flag=$(tmux display-message -p "#{${d.edge}}")''
              ''if [ "$edge_flag" = "0" ]; then''
              ("  " + ''tmux swap-pane -t "{${d.word}-of}"'')
              ''elif [ "$pane_${d.fullDim}" -eq "$window_${d.fullDim}" ]; then''
              "  return"
              "else"
              ("  " + ''target_token="{${d.token}}"'')
              "  join_flags=(${d.joinFlags})"
              "fi"
              ";;"
            ]
          ) directions}
          esac

          if [ -n "$target_token" ]; then
            target_pane=$(tmux display-message -p -t "$target_token" "#{pane_id}")
            if [ "$target_pane" = "$pane_id" ]; then
              while IFS= read -r target_pane; do
                if [ "$target_pane" != "$pane_id" ]; then
                  break
                fi
              done <<EOF
        $(tmux list-panes -F "#{pane_id}")
        EOF
            fi
            if [ -z "$target_pane" ] || [ "$target_pane" = "$pane_id" ]; then
              return
            fi
            tmux move-pane -d "''${join_flags[@]}" -s "$pane_id" -t "$target_pane"
          fi

          tmux select-pane -t "$pane_id"
        }

        move_pane_to_window() {
          local target_n="$1"
          local current_window max_window

          current_window=$(tmux display-message -p "#{window_index}")
          if [ "''${current_window}" = "''${target_n}" ]; then
            return
          fi

          if tmux list-windows -F "#{window_index}" | grep -q "^''${target_n}$"; then
            # shellcheck disable=SC2046
            tmux join-pane $(join_direction) -t ":''${target_n}"
          else
            max_window=$(tmux list-windows -F "#{window_index}" | sort -n | tail -1)
            if [ "''${target_n}" -gt "''${max_window}" ]; then
              tmux break-pane
            else
              tmux break-pane -t ":''${target_n}"
            fi
          fi
        }

        if ! declare -F "$1" >/dev/null; then
          printf 'tmux commands: unknown command %s\n' "$1" >&2
          exit 1
        fi
        "$@"
      '';

      home.sessionVariables.TMUX_TMPDIR = tmuxTmpdir;

      stubbe.setup.tmuxTmpdir = lib.mkIf (config.host.platform == "android") {
        script = ''mkdir -p -m 0700 "${tmuxTmpdir}"'';
      };

      # User units, which nothing runs on Android: nix-on-droid has no init,
      # so tmux is started from the shell there.
      systemd.user = lib.mkIf (config.host.platform != "android") {
        sessionVariables.TMUX_TMPDIR = tmuxTmpdir;

        sockets.tmux = {
          Unit = {
            Description = "tmux server socket";
            X-SwitchMethod = "keep-old";
          };
          Socket = {
            ListenStream = "%t/${runtimeSubdir}/tmux-%U/default";
            SocketMode = "0600";
            DirectoryMode = "0700";
          };
          Install.WantedBy = [ "sockets.target" ];
        };

        services.tmux = {
          Unit = {
            Description = "tmux server";
            X-SwitchMethod = "keep-old";
          };
          Service = {
            ExecStart = "${tmuxServer}";
            ManagedOOMPreference = "avoid";
          };
        };
      };

      programs.tmux = {
        enable = true;
        secureSocket = false;
        sensibleOnTop = true;
        plugins = [ pkgs.tmuxPlugins.yank ];
        extraConfig = ''
          set -g prefix M-Space
          bind M-Space send-prefix

          set -g @stubbe_commands "$HOME/.config/tmux/scripts/commands.sh"

          bind -N "Reload config" -n M-r run-shell -b "#{@stubbe_commands} reload"
          bind -N "Reload config" -n M-R run-shell -b "#{@stubbe_commands} reload"

          set -g  default-terminal    "tmux-256color"
          set -ga terminal-overrides  '*:Ss=\E[%p1%d q:Se=\E[ q'
          set -as terminal-features   ",*:RGB:hyperlinks"
          set -as terminal-overrides  ",xterm-ghostty:Eneks@:Dseks@"
          set -g  set-clipboard       on
          set -g  allow-passthrough   on
          set-environment -g COLORTERM "truecolor"

          ${lib.concatMapStrings (d: ''
            bind -N "Focus pane ${d.word}" -n M-${d.key} select-pane -${d.flag}
            bind -N "Resize pane ${d.word}" -n -r M-C-${d.key} resize-pane -${d.flag}
            bind -N "Move pane ${d.word}" -n M-S-${d.key} run-shell -b "#{@stubbe_commands} move_pane ${d.flag}"
          '') directions}
          bind -N "Focus next pane" -n M-W select-pane -t :.+
          bind -N "Focus previous pane" -n M-w select-pane -t :.-
          bind -N "Toggle pane zoom" -n M-z resize-pane -Z
          bind -N "Split horizontal (50%)" -n M-| split-pane -h -c "#{pane_current_path}"
          bind -N "Split horizontal (30%)" -n M-\\ split-pane -h -l '30%' -c "#{pane_current_path}"
          bind -N "Split vertical (50%)" -n M-- split-pane -v -c "#{pane_current_path}"
          bind -N "Split vertical (30%)" -n M-_ split-pane -v -l '30%' -c "#{pane_current_path}"
          bind -N "Kill pane (double-tap if pinned)" -n M-q run-shell -b "#{@stubbe_commands} kill_pane"
          bind -N "Toggle mark / join pane" Space run-shell -b "#{@stubbe_commands} toggle_mark_join"

          ${lib.concatMapStrings (w: ''
            bind -N "Go to window ${toString w.n}" -n M-${w.digit} select-window -t ${toString w.n}
            bind -N "Move pane to window ${toString w.n}" -n M-${w.shift} run-shell "#{@stubbe_commands} move_pane_to_window ${toString w.n}"
          '') windowKeys}
          bind -N "Next window" -n M-n if -F "#{>:#{session_windows},1}" next-window
          bind -N "Previous window" -n M-b if -F "#{>:#{session_windows},1}" previous-window
          bind -N "New window in current path" -n M-e new-window -c "#{pane_current_path}"
          bind -N "Window picker" -n M-s choose-window
          bind -N "Rename window" -n M-c command-prompt -I "#W" "rename-window -- \"%%\""
          bind -N "Kill window (double-tap if pinned)" -n M-Q run-shell -b "#{@stubbe_commands} kill_window"

          bind -N "Detach from session" -n M-d detach-client
          bind -N "Session picker" -n M-S choose-session
          bind -N "Next session" -n M-N if -F "#{>:#{server_sessions},1}" "switch-client -n"
          bind -N "Previous session" -n M-B if -F "#{>:#{server_sessions},1}" "switch-client -p"
          bind -N "Kill session" -n M-x kill-session
          bind -N "Session popup" -n M-i display-popup -B -w 70% -h 75% -E "tmux-pick-session"

          bind -N "Next layout" -n M-t next-layout
          bind -N "Previous layout" -n M-T previous-layout

          bind -N "Enter copy mode" -n M-v copy-mode
          bind -N "Paste buffer" -n M-p paste-buffer
          bind -N "Begin selection" -T copy-mode-vi v send-keys -X begin-selection

          bind -N "Project picker" -n M-f new-window -c "#{pane_current_path}" "tmux-pick-project"
          bind -N "Directory picker" -n M-D new-window -c "#{pane_current_path}" "tmux-pick-directory"

          bind -N "Toggle lazygit" -n M-g run-shell -b "#{@stubbe_commands} toggle_lazygit_window"
          ${lib.concatMapStrings (w: ''
            bind -N "Toggle ${w.window}" -n ${w.key} run-shell -b "#{@stubbe_commands} toggle_window ${w.window} ${
              lib.getExe launchers.${w.launcher}
            }"
          '') toolWindows}
          bind -N "Toggle pin" p run-shell -b "#{@stubbe_commands} toggle_pin"
          bind -N "Toggle pin" -n M-P run-shell -b "#{@stubbe_commands} toggle_pin"
          bind -N "Kill server (double-tap)" X run-shell -b "#{@stubbe_commands} kill_server_confirm"

          set-hook -g session-created[50] "run-shell -b \"#{@stubbe_commands} session_init\""
          set-hook -g client-attached "run-shell -b \"#{@stubbe_commands} client_changed #{q:hook_session_name}\""
          set-hook -g client-session-changed "run-shell -b \"#{@stubbe_commands} client_changed #{q:hook_session_name}\""
          set-hook -g client-detached "run-shell -b \"#{@stubbe_commands} set_ssh_flag #{q:hook_session_name}\""
          set-hook -g window-unlinked[55] "run-shell -b \"#{@stubbe_commands} save_pins\""
          run-shell -b "#{@stubbe_commands} session_init"
          run-shell -b "#{@stubbe_commands} set_ssh_flag"

          set -g status-position top
          set -g status-style bg=default,fg=default
          set -g status-justify left
          set -g status-left "#[bg=default,bold]#{?client_prefix,#[fg=${p.mauve}] 󰏘 ,#{?pane_marked_set,#[fg=${p.mauve}] 󰗝 ,#[fg=${p.text}]  }}"
          set -g status-right-length 100
          set -g status-right "#{?#{==:#{@stubbe_ssh},1},#{s|\\(([^)]+)\\)|(#[fg=${p.yellow}]\\1#[fg=default])|r:session_name},#S}"
          set -g window-status-format          " #I:#W#(#{@stubbe_commands} branch_ticket '#{pane_current_path}')#{?#{@pinned}, 󰤱,} "
          set -g window-status-current-format  "#[bg=${p.mauve},fg=${p.base},bold]  #I:#W#(#{@stubbe_commands} branch_ticket '#{pane_current_path}') #{?#{@pinned},󰤱 ,}#{?window_zoomed_flag, 󰊓 , }"
          set -g window-status-current-style   none
          set -g window-status-activity-style  none
          set -g mode-style                    bg=${p.mauve},fg=${p.base}
          set -g pane-active-border-style      bg=${p.base},fg=${p.mauve}
          set -g pane-border-style             bg=${p.base},fg=${p.lavender}
          set -g message-style                 bg=${p.base},fg=${p.lavender}
          set -g message-command-style         bg=${p.base},fg=${p.lavender}
          set -g copy-mode-match-style         bg=${p.lavender},fg=${p.base}
          set -g copy-mode-mark-style          bg=${p.base},fg=${p.lavender}
          set -g copy-mode-current-match-style bg=${p.red},fg=${p.base}

          set -g  base-index        1
          setw -g pane-base-index   1
          set -g  renumber-windows  on
          set -g  focus-events      on
          set -g  extended-keys     on
          set -g  detach-on-destroy on
          set -g  update-environment "SSH_AUTH_SOCK SSH_CONNECTION SSH_CLIENT SSH_TTY DISPLAY"
          set -sg escape-time       50
          set -g  history-limit     1000000
          set -g  mouse             off
          setw -g mode-keys         vi
          set -g  visual-activity   off
          set -g  monitor-activity  on
        '';
      };
    };
}
