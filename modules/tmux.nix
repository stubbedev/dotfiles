# tmux, with lazy-tmux for session persistence.
#
# lazy-tmux replaced resurrect+continuum: it snapshots window names, layouts,
# pane commands and shell scrollback, and restores ONE session on demand
# (`wakeup --session`) instead of every session at server start. Its claude
# integration records the Claude Code session id and restores the pane as
# `claude --resume <id>`, so Alt+f on a repo brings the conversation back
# rather than a fresh one.
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
    in
    lib.mkIf config.features.desktop {
      home.packages = [ pkgs.lazy-tmux ];

      # The command palette every bind and hook in tmux.conf dispatches to.
      # The tmux-session check reads this deployed file back out of
      # `xdg.configFile`, so the tested bytes are the shipped bytes.
      home.file.".config/tmux/scripts/commands.sh" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash

          CLAUDE_WINDOW_NAME="claude"
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
              # A restored window can still land on a bare shell — lazy-tmux replays the
              # pane command, but an older snapshot (or a denied command) leaves the
              # shell. Respawn so the toggle always lands on a live pane.
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

          session_init() {
            local session_name
            local pane_id
            local target
            local current_path
            local has_git=0

            session_name=$(tmux display-message -p -F "#{hook_session_name}")
            if [ -z "$session_name" ]; then
              session_name=$(tmux display-message -p -F "#S")
            fi

            pane_id=$(tmux display-message -p -F "#{hook_pane}")
            if [ -z "$pane_id" ]; then
              pane_id=$(tmux display-message -p -F "#{pane_id}")
            fi

            current_path=$(tmux display-message -p -t "$pane_id" -F "#{pane_current_path}")
            if [ -n "$current_path" ] && git -C "$current_path" rev-parse --git-dir >/dev/null 2>&1; then
              has_git=1
            fi

            if [ -n "$session_name" ]; then
              target="$session_name"
            else
              target=$(tmux display-message -p -F "#S")
            fi

            tmux set-option -q -t "$target" @stubbe_has_git "$has_git"
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
            local session_name
            local pane_id
            local current_path
            local has_git=0

            session_name=$(tmux display-message -p -F "#S")
            pane_id=$(tmux display-message -p -F "#{pane_id}")
            current_path=$(tmux display-message -p -t "$pane_id" -F "#{pane_current_path}")

            if [ -n "$current_path" ] && git -C "$current_path" rev-parse --git-dir >/dev/null 2>&1; then
              has_git=1
            fi

            tmux set-option -q -t "$session_name" @stubbe_has_git "$has_git"
          }

          toggle_lazygit_window() {
            refresh_session_git_flag

            if [ "$(tmux show-option -qv @stubbe_has_git)" != "1" ]; then
              return
            fi

            if ! command -v tmux-lazy-git >/dev/null 2>&1; then
              return
            fi

            toggle_window "lazygit" tmux-lazy-git
          }

          toggle_sysmon_window() {
            if ! command -v tmux-system-monitor >/dev/null 2>&1; then
              return
            fi

            toggle_window "sysmon" tmux-system-monitor
          }

          toggle_lazydocker_window() {
            if ! command -v tmux-lazy-docker >/dev/null 2>&1; then
              return
            fi

            toggle_window "lazydocker" tmux-lazy-docker
          }

          toggle_claude_window() {
            if ! command -v tmux-claude >/dev/null 2>&1; then
              return
            fi

            local current_path worktree current_window
            current_path=$(tmux display-message -p -F "#{pane_current_path}")
            current_window=$(tmux display-message -p '#W')
            worktree=$(git -C "$current_path" rev-parse --show-toplevel 2>/dev/null)

            if [ -z "$worktree" ]; then
              toggle_window "$CLAUDE_WINDOW_NAME" tmux-claude
              return
            fi

            if [ "$current_window" = "$CLAUDE_WINDOW_NAME" ]; then
              tmux last-window 2>/dev/null || true
              return 0
            fi

            local target sess win wname wpath wt
            while IFS=$'\t' read -r sess win wname wpath; do
              [ "$wname" = "$CLAUDE_WINDOW_NAME" ] || continue
              wt=$(git -C "$wpath" rev-parse --show-toplevel 2>/dev/null)
              if [ "$wt" = "$worktree" ]; then
                target="''${sess}:''${win}"
                break
              fi
            done < <(tmux list-windows -a -F '#{session_name}	#{window_index}	#{window_name}	#{pane_current_path}')

            if [ -n "$target" ]; then
              local current_session target_session
              current_session=$(tmux display-message -p '#S')
              target_session="''${target%%:*}"
              if [ "$target_session" = "$current_session" ]; then
                tmux select-window -t "$target"
              else
                tmux switch-client -t "$target"
              fi
              return 0
            fi

            tmux new-window -c "$current_path" -n "$CLAUDE_WINDOW_NAME" tmux-claude
          }

          claude_inline_pane() {
            if ! command -v tmux-claude >/dev/null 2>&1; then
              return
            fi
            local current_path
            current_path=$(tmux display-message -p -F "#{pane_current_path}")
            tmux respawn-pane -k -c "$current_path" \
              "zsh -ic 'tmux rename-window ''${CLAUDE_WINDOW_NAME}; tmux-claude --inline; tmux set-window-option automatic-rename on; exec zsh -i'"
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

          # lazy-tmux carries over no pane options, so @pinned — and with it the
          # double-tap guard on M-q/M-Q — would silently vanish on restore. Dumped on
          # every toggle_pin (the only place @pinned changes) and replayed by
          # tmux-pick-project after a wakeup; the session/window/pane keys survive
          # because lazy-tmux restores windows and panes at their saved indices.
          save_pins() {
            mkdir -p "''${PINNED_STATE%/*}"
            tmux list-panes -a -F '#{@pinned}	#{session_name}	#{window_index}	#{pane_index}' |
              sed -n 's/^1	//p' > "$PINNED_STATE.tmp"
            mv "$PINNED_STATE.tmp" "$PINNED_STATE"
          }

          restore_pins() {
            [ -f "$PINNED_STATE" ] || return 0
            local sess win pane
            while IFS=$'\t' read -r sess win pane; do
              [ -n "$pane" ] || continue
              tmux set -p -t "=$sess:$win.$pane" @pinned 1 2>/dev/null || true
            done < "$PINNED_STATE"
          }

          # The lazy-tmux daemon only ticks every few minutes; detaching or killing the
          # server is the usual prelude to a reboot, so flush the snapshots right then
          # instead of betting on the next tick. Scrollback settings come from
          # ~/.config/lazy-tmux/lazy-tmux.toml.
          save_state() {
            command -v lazy-tmux >/dev/null 2>&1 || return 0
            lazy-tmux save --all >/dev/null 2>&1
          }

          # Close a session without losing it: snapshot first (scrollback settings come
          # from lazy-tmux.toml), then let lazy-tmux kill it. The client is moved to
          # another session first — detach-on-destroy would otherwise drop it to the bare
          # terminal. `tmux-pick-session` (M-d in zsh) lists it as sleeping afterwards.
          sleep_session() {
            local current other
            if ! command -v lazy-tmux >/dev/null 2>&1; then
              return 0
            fi

            current=$(tmux display-message -p '#S')
            other=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -vxF "$current" | head -1)
            [ -n "$other" ] && tmux switch-client -t "=$other"

            if ! lazy-tmux sleep --session "$current" >/dev/null 2>&1; then
              tmux display-message "lazy-tmux: could not sleep $current"
            fi
          }

          kill_pane() {
            local pending pane_id window_id

            pane_id=$(tmux display-message -p "#{pane_id}")
            if ! pane_is_pinned "$pane_id"; then
              tmux kill-pane
              return
            fi

            pending=$(tmux display-message -p "#{@kill_pane_pending}")
            if [ "$pending" = "1" ]; then
              tmux kill-pane
              return
            fi

            window_id=$(tmux display-message -p "#{window_id}")
            tmux set -p -t "$pane_id" @kill_pane_pending 1
            pending_animation "$pane_id" "$window_id" pane
          }

          kill_window() {
            local pending pane_id window_id any_pinned pid

            window_id=$(tmux display-message -p "#{window_id}")

            any_pinned=0
            while IFS= read -r pid; do
              if pane_is_pinned "$pid"; then
                any_pinned=1
                break
              fi
            done < <(tmux list-panes -t "$window_id" -F "#{pane_id}")

            if [ "$any_pinned" != "1" ]; then
              tmux kill-window
              return
            fi

            pending=$(tmux display-message -p "#{@kill_window_pending}")
            if [ "$pending" = "1" ]; then
              tmux kill-window
              return
            fi

            pane_id=$(tmux display-message -p "#{pane_id}")
            tmux set -w -t "$window_id" @kill_window_pending 1
            pending_animation "$pane_id" "$window_id" window
          }

          kill_server_confirm() {
            local pending
            pending=$(tmux show-option -gv @kill_server_pending 2>/dev/null)
            if [ "$pending" = "1" ]; then
              save_state
              tmux kill-server
              return
            fi

            tmux set -g @kill_server_pending 1
            sleep 1.5
            tmux set -g @kill_server_pending 0 2>/dev/null
          }

          toggle_mark_join() {
            local pane_marked pane_marked_set pane_width pane_height

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

            pane_width=$(tmux display-message -p "#{pane_width}")
            pane_height=$(tmux display-message -p "#{pane_height}")
            if [ "$pane_width" -gt "$((pane_height * 2))" ]; then
              tmux join-pane -h
            else
              tmux join-pane
            fi
          }

          # tmux runs status strings through strftime and then format expansion, but the
          # values it substitutes in (#W, #() output) are inserted literally and never
          # re-scanned — checked against the drawn bar, where a window named 'a#Sb' draws
          # as 'a#Sb' and a '%H' in a name stays '%H'. So any already-substituted text
          # this function feeds back through either pass has to be escaped ('#'->'##',
          # '%'->'%%') or the label mutates mid-animation: a window named 'a#Sb' would
          # flash the session name, '50%H' the current hour.
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
            # %q the interpolated values: the trap body is eval'd after the function has
            # returned, so the locals are gone and they cannot be expanded lazily.
            local restore
            printf -v restore 'tmux set -wu -t %q window-status-current-format 2>/dev/null; tmux set %s -t %q %s 0 2>/dev/null' \
              "$win_id" "$flag_scope" "$flag_target" "$flag_name"
            trap "$restore" EXIT INT TERM

            shopt -s extglob
            local raw base_style template
            raw=$(tmux show-options -gqv window-status-current-format)
            [[ "$raw" =~ ^(#\[[^]]*\]) ]] && base_style="''${BASH_REMATCH[1]}"
            template="''${raw//#\[*([^]])\]/}"

            # display-message expands #{...} but silently drops #(...) — only the
            # status-line draw loop runs those jobs. Left unresolved, the frozen frames
            # lose whatever the jobs contribute (the branch ticket), so tapping M-q/M-Q
            # visibly shortens the label before the bar snaps back. Run them here.
            # Built left to right rather than by substitution, so job output that itself
            # looks like a job can never be re-scanned.
            local rest="$template" expanded="" pre job out
            while [[ "$rest" == *'#('* ]]; do
              pre="''${rest%%#(*}"
              rest="''${rest#*#(}"
              job="''${rest%%)*}"
              rest="''${rest#*)}"
              out=$(eval "$(tmux display-message -p -t "$win_id" "$job")" 2>/dev/null)
              # Only '%' is escaped here. The bar re-scans job output for '#' directives
              # but does not strftime it; display-message does both, so escaping '#' too
              # would freeze a literal '#S' where the bar had already resolved it.
              expanded+="$pre''${out//%/%%}"
            done
            template="$expanded$rest"

            local rendered
            rendered=$(tmux display-message -p -t "$win_id" "$template")

            local -a chars=()
            while IFS= read -r c; do
              chars+=("$c")
            done < <(LC_ALL=C.UTF-8 grep -o . <<<"$rendered")

            # Escaped once up front, and by parameter expansion rather than a subshell:
            # the frames are rebuilt every tick, so anything per-char here multiplies out.
            # chars stays unescaped — it still counts rendered cells, which the fill walks.
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

            # Keep the filled bar on screen briefly so the keypress window extends
            # visibly past the animation's final frame.
            sleep 0.2
          }

          reload_animation() {
            local chars=("⡿" "⣟" "⣯" "⣷" "⣾" "⣽" "⣻" "⢿")
            local original restore
            original=$(tmux show-option -gqv status-left)
            # %q, so a theme string containing a quote cannot break out of the restore
            # command and leave status-left wiped.
            printf -v restore 'tmux set -g status-left %q 2>/dev/null' "$original"
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
            # Bound to both M-r and M-R. In a zsh pane, hand off to zsh's own reload
            # widget (it re-sources tmux and exec's a fresh zsh, with no echoed text);
            # otherwise just reload the tmux config here.
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
            L)
              edge_flag=$(tmux display-message -p "#{pane_at_left}")
              if [ "$edge_flag" = "0" ]; then
                tmux swap-pane -t "{left-of}"
              elif [ "$pane_height" -eq "$window_height" ]; then
                return
              else
                target_token="{left}"
                join_flags=(-b -h)
              fi
              ;;
            R)
              edge_flag=$(tmux display-message -p "#{pane_at_right}")
              if [ "$edge_flag" = "0" ]; then
                tmux swap-pane -t "{right-of}"
              elif [ "$pane_height" -eq "$window_height" ]; then
                return
              else
                target_token="{right}"
                join_flags=(-h)
              fi
              ;;
            U)
              edge_flag=$(tmux display-message -p "#{pane_at_top}")
              if [ "$edge_flag" = "0" ]; then
                tmux swap-pane -t "{up-of}"
              elif [ "$pane_width" -eq "$window_width" ]; then
                return
              else
                target_token="{top}"
                join_flags=(-b)
              fi
              ;;
            D)
              edge_flag=$(tmux display-message -p "#{pane_at_bottom}")
              if [ "$edge_flag" = "0" ]; then
                tmux swap-pane -t "{down-of}"
              elif [ "$pane_width" -eq "$window_width" ]; then
                return
              else
                target_token="{bottom}"
              fi
              ;;
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
            local current_window pane_width pane_height max_window

            current_window=$(tmux display-message -p "#{window_index}")
            if [ "''${current_window}" = "''${target_n}" ]; then
              return
            fi

            if tmux list-windows -F "#{window_index}" | grep -q "^''${target_n}$"; then
              pane_width=$(tmux display-message -p "#{pane_width}")
              pane_height=$(tmux display-message -p "#{pane_height}")
              if [ "$pane_width" -gt "$((pane_height * 2))" ]; then
                tmux join-pane -h -t ":''${target_n}"
              else
                tmux join-pane -t ":''${target_n}"
              fi
            else
              max_window=$(tmux list-windows -F "#{window_index}" | sort -n | tail -1)
              if [ "''${target_n}" -gt "''${max_window}" ]; then
                tmux break-pane
              else
                tmux break-pane -t ":''${target_n}"
              fi
            fi
          }

          case "$1" in
          "toggle_pin")               toggle_pin ;;
          "save_pins")                save_pins ;;
          "restore_pins")             restore_pins ;;
          "save_state")               save_state ;;
          "sleep_session")            sleep_session ;;
          "kill_pane")                kill_pane ;;
          "kill_window")              kill_window ;;
          "kill_server_confirm")      kill_server_confirm ;;
          "toggle_mark_join")         toggle_mark_join ;;
          "toggle_lazygit_window")    toggle_lazygit_window ;;
          "toggle_sysmon_window")     toggle_sysmon_window ;;
          "toggle_lazydocker_window") toggle_lazydocker_window ;;
          "toggle_claude_window")     toggle_claude_window ;;
          "claude_inline_pane")       claude_inline_pane ;;
          "move_pane")                move_pane "$2" ;;
          "move_pane_to_window")      move_pane_to_window "$2" ;;
          "session_init")             session_init ;;
          "set_ssh_flag")             set_ssh_flag "$2" ;;
          "branch_ticket")            branch_ticket "$2" ;;
          "reload")                   reload ;;
          "pending_animation")        pending_animation "$2" "$3" "$4" ;;
          esac

        '';
      };

      # Single source of truth for save behaviour: the daemon, `save_state` on
      # detach and the Alt+f restore path all read this instead of repeating
      # flags at every call site. scrollback is opt-in upstream. 1m matches the
      # old @continuum-save-interval and costs ~36K per live session with 10k
      # lines of scrollback, so stretching the interval is not worth it.
      home.file.".config/lazy-tmux/lazy-tmux.toml".text = ''
        save_interval = "1m"

        [scrollback]
        enabled = true
        lines = 10000
      '';

      programs.tmux = {
        enable = true;
        sensibleOnTop = true;
        plugins = [ pkgs.tmuxPlugins.yank ];
        extraConfig = ''
          # ==============================================
          # Prefix Key Configuration
          # ==============================================
          set -g prefix M-Space
          bind M-Space send-prefix

          set -g @stubbe_commands "$HOME/.config/tmux/scripts/commands.sh"

          # Reload — M-r and M-R behave identically (see commands.sh `reload`).
          bind -n M-r run-shell -b "#{@stubbe_commands} reload"
          bind -n M-R run-shell -b "#{@stubbe_commands} reload"

          # ==============================================
          # Terminal & Color Configuration
          # ==============================================
          set -g  default-terminal    "tmux-256color"
          set -ga terminal-overrides  ",*256col*:Tc"
          set -ga terminal-overrides  '*:Ss=\E[%p1%d q:Se=\E[ q'
          set -as terminal-features   ",*:RGB"
          # Pass OSC 8 hyperlinks through to the outer terminal (alacritty) so its
          # built-in URL hint (hover underline + pointer, click to open) sees them.
          set -as terminal-features   ",*:hyperlinks"
          set -g  set-clipboard       on
          set -g  allow-passthrough   on
          set-environment -g COLORTERM "truecolor"

          # ==============================================
          # Pane Navigation (Alt + arrows)
          # ==============================================
          bind -n M-Left  select-pane -L           # Focus pane left
          bind -n M-Right select-pane -R           # Focus pane right
          bind -n M-Up    select-pane -U           # Focus pane up
          bind -n M-Down  select-pane -D           # Focus pane down
          bind -n M-W     select-pane -t :.+       # Focus next pane
          bind -n M-w     select-pane -t :.-       # Focus previous pane

          # ==============================================
          # Pane Resizing (Alt+Ctrl+arrows, mirrors SUPER_CTRL in Hyprland)
          # ==============================================
          bind -n -r M-C-Left  resize-pane -L      # Resize pane left
          bind -n -r M-C-Right resize-pane -R      # Resize pane right
          bind -n -r M-C-Up    resize-pane -U      # Resize pane up
          bind -n -r M-C-Down  resize-pane -D      # Resize pane down

          # ==============================================
          # Pane Management
          # ==============================================
          bind -n M-z       resize-pane -Z                                         # Toggle pane zoom
          bind -n M-S-Left  run-shell -b "#{@stubbe_commands} move_pane L"         # Move pane left
          bind -n M-S-Right run-shell -b "#{@stubbe_commands} move_pane R"         # Move pane right
          bind -n M-S-Up    run-shell -b "#{@stubbe_commands} move_pane U"         # Move pane up
          bind -n M-S-Down  run-shell -b "#{@stubbe_commands} move_pane D"         # Move pane down
          bind -n M-|       split-pane -h          -c "#{pane_current_path}"       # Split horizontal (50%)
          bind -n M-\\      split-pane -h -l '30%' -c "#{pane_current_path}"       # Split horizontal (30%)
          bind -n M--       split-pane -v          -c "#{pane_current_path}"       # Split vertical (50%)
          bind -n M-_       split-pane -v -l '30%' -c "#{pane_current_path}"       # Split vertical (30%)
          bind -n M-q       run-shell -b "#{@stubbe_commands} kill_pane"           # Kill pane (double-tap if pinned)
          bind    Space     run-shell -b "#{@stubbe_commands} toggle_mark_join"    # Toggle mark / join pane

          # ==============================================
          # Move Pane to Window (Alt+Shift+Number)
          # ==============================================
          bind -n M-!  run-shell "#{@stubbe_commands} move_pane_to_window 1"       # Move pane to window 1
          bind -n M-@  run-shell "#{@stubbe_commands} move_pane_to_window 2"       # Move pane to window 2
          bind -n M-\# run-shell "#{@stubbe_commands} move_pane_to_window 3"       # Move pane to window 3
          bind -n M-\$ run-shell "#{@stubbe_commands} move_pane_to_window 4"       # Move pane to window 4
          bind -n M-%  run-shell "#{@stubbe_commands} move_pane_to_window 5"       # Move pane to window 5
          bind -n M-^  run-shell "#{@stubbe_commands} move_pane_to_window 6"       # Move pane to window 6
          bind -n M-&  run-shell "#{@stubbe_commands} move_pane_to_window 7"       # Move pane to window 7
          bind -n M-*  run-shell "#{@stubbe_commands} move_pane_to_window 8"       # Move pane to window 8
          bind -n M-(  run-shell "#{@stubbe_commands} move_pane_to_window 9"       # Move pane to window 9
          bind -n M-)  run-shell "#{@stubbe_commands} move_pane_to_window 10"      # Move pane to window 10

          # ==============================================
          # Window Navigation & Management
          # ==============================================
          bind -n M-1 select-window -t 1                                           # Go to window 1
          bind -n M-2 select-window -t 2                                           # Go to window 2
          bind -n M-3 select-window -t 3                                           # Go to window 3
          bind -n M-4 select-window -t 4                                           # Go to window 4
          bind -n M-5 select-window -t 5                                           # Go to window 5
          bind -n M-6 select-window -t 6                                           # Go to window 6
          bind -n M-7 select-window -t 7                                           # Go to window 7
          bind -n M-8 select-window -t 8                                           # Go to window 8
          bind -n M-9 select-window -t 9                                           # Go to window 9
          bind -n M-0 select-window -t 10                                          # Go to window 10
          bind -n M-n if-shell '[ "$(tmux list-windows | wc -l)" -gt 1 ]' next-window     # Next window
          bind -n M-b if-shell '[ "$(tmux list-windows | wc -l)" -gt 1 ]' previous-window # Previous window
          bind -n M-e new-window -c "#{pane_current_path}"                         # New window in current path
          bind -n M-s choose-window                                                # Window picker
          bind -n M-c command-prompt -I "#W" "rename-window -- \"%%\""             # Rename window
          bind -n M-Q run-shell -b "#{@stubbe_commands} kill_window"               # Kill window (double-tap if pinned)

          # ==============================================
          # Session Management
          # ==============================================
          bind -n M-d detach-client                                                                                 # Detach from session
          bind -n M-S choose-session                                                                                # Session picker
          bind -n M-N if-shell '[ "$(tmux list-sessions -F "#{session_name}" | wc -l)" -gt 1 ]' 'switch-client -n'  # Next session
          bind -n M-B if-shell '[ "$(tmux list-sessions -F "#{session_name}" | wc -l)" -gt 1 ]' 'switch-client -p'  # Previous session
          bind -n M-x run-shell -b "#{@stubbe_commands} sleep_session"                                              # Sleep session (save + close)

          # ==============================================
          # Layout Management
          # ==============================================
          bind -n M-t next-layout                                                  # Next layout
          bind -n M-T previous-layout                                              # Previous layout

          # ==============================================
          # Copy Mode & Clipboard
          # ==============================================
          bind -n M-v copy-mode                                                    # Enter copy mode
          bind -n M-p paste-buffer                                                 # Paste buffer
          bind -T copy-mode-vi v send-keys -X begin-selection                      # Begin selection

          # ==============================================
          # Custom Scripts & FZF Integration
          # ==============================================
          bind -n M-f new-window -c "#{pane_current_path}" "tmux-pick-project"       # FZF project picker
          bind -n M-D new-window -c "#{pane_current_path}" "tmux-pick-directory"     # FZF directory picker
          bind -n M-h run-shell -b "#{@stubbe_commands} toggle_claude_window"        # Toggle claude window
          bind -n M-H run-shell -b "#{@stubbe_commands} claude_inline_pane"          # Run claude in current pane

          # ==============================================
          # Lazy Window Toggles (lazygit, sysmon, lazydocker)
          # ==============================================
          set-hook -g session-created[50] "run-shell -b \"#{@stubbe_commands} session_init\""
          set-hook -g client-attached "run-shell -b \"#{@stubbe_commands} set_ssh_flag #{hook_session_name}\""
          set-hook -g client-session-changed "run-shell -b \"#{@stubbe_commands} set_ssh_flag #{hook_session_name}\""
          set-hook -g client-detached "run-shell -b \"#{@stubbe_commands} set_ssh_flag #{hook_session_name}\""
          set-hook -g client-detached[60] "run-shell -b \"#{@stubbe_commands} save_state\""
          # @pinned is a pane option and no restore path carries pane options over, so
          # replay the dump on attach and on session switch. That covers every way a
          # session comes back: Alt+f (tmux-pick-project), M-d (tmux-pick-session), the
          # M-i picker, and a bare `lazy-tmux wakeup`.
          set-hook -g client-attached[55] "run-shell -b \"#{@stubbe_commands} restore_pins\""
          set-hook -g client-session-changed[55] "run-shell -b \"#{@stubbe_commands} restore_pins\""
          run-shell -b "#{@stubbe_commands} session_init"
          run-shell -b "#{@stubbe_commands} set_ssh_flag"
          bind -n M-g run-shell -b "#{@stubbe_commands} toggle_lazygit_window"     # Toggle lazygit
          bind -n M-a run-shell -b "#{@stubbe_commands} toggle_sysmon_window"      # Toggle sysmon
          bind -n M-A run-shell -b "#{@stubbe_commands} toggle_lazydocker_window"  # Toggle lazydocker

          # ==============================================
          # Pinned Windows (double-tap to kill)
          # ==============================================
          bind    p   run-shell -b "#{@stubbe_commands} toggle_pin"                # Toggle pin (prefix)
          bind -n M-P run-shell -b "#{@stubbe_commands} toggle_pin"                # Toggle pin
          bind    X   run-shell -b "#{@stubbe_commands} kill_server_confirm"       # Kill server (double-tap)

          # ==============================================
          # Theme (Catppuccin Mocha)
          # ==============================================
          set -g status-position top
          set -g status-style bg=default,fg=default
          set -g status-justify left
          set -g status-left "#[bg=default,bold]#{?client_prefix,#[fg=${p.mauve}] 󰏘 ,#{?pane_marked_set,#[fg=${p.mauve}] 󰗝 ,#[fg=${p.text}]  }}"
          set -g status-right-length 100
          set -g status-right "#{?#{==:#{@stubbe_ssh},1},#{s|\\(([^)]+)\\)|(#[fg=${p.yellow}]\\1#[fg=default])|r:session_name},#S}"
          set -g window-status-format          " #I:#W#(#{@stubbe_commands} branch_ticket '#{pane_current_path}')#{?#{@pinned}, 󰤱,} "
          set -g window-status-current-format  "#[bg=${p.mauve},fg=${p.base},bold]  #I:#W#(#{@stubbe_commands} branch_ticket '#{pane_current_path}') #{?#{@pinned},󰤱 ,}#{?window_zoomed_flag, 󰊓 , }"
          set -g window-status-activity-style  none
          set -g mode-style                    bg=${p.mauve},fg=${p.base}
          set -g pane-active-border-style      bg=${p.base},fg=${p.mauve}
          set -g pane-border-style             bg=${p.base},fg=${p.lavender}
          set -g message-style                 bg=${p.base},fg=${p.lavender}
          set -g message-command-style         bg=${p.base},fg=${p.lavender}
          set -g copy-mode-match-style         bg=${p.lavender},fg=${p.base}
          set -g copy-mode-mark-style          bg=${p.base},fg=${p.lavender}
          set -g copy-mode-current-match-style bg=${p.red},fg=${p.base}

          # ==============================================
          # General Settings
          # ==============================================
          set -g  base-index        1          # Start window numbering at 1
          setw -g pane-base-index   1          # Start pane numbering at 1
          set -g  renumber-windows  on         # Renumber windows when one is closed
          set -g  focus-events      on         # Enable focus events for Neovim
          set -g  extended-keys     on         # Pass kitty keyboard protocol sequences through
          set -g  detach-on-destroy on         # Detach when session is destroyed
          set -g  update-environment "SSH_AUTH_SOCK SSH_CONNECTION SSH_CLIENT SSH_TTY DISPLAY"
          set -sg escape-time       50         # Reduce escape delay
          set -g  history-limit     1000000    # Scrollback buffer size
          set -g  mouse             off        # Disable mouse
          setw -g mode-keys         vi         # Vi mode for copy mode
          set -g  visual-activity   off        # Don't show activity message
          set -g  monitor-activity  on         # Monitor background window activity


          # ==============================================
          # lazy-tmux autosave daemon
          # ==============================================
          # Started per tmux server, killed with it. The daemon flocks a file
          # keyed by the tmux socket path, so re-sourcing this file on M-r
          # exits non-zero instead of stacking a second daemon — hence the
          # `|| true`. Interval and scrollback come from lazy-tmux.toml.
          run-shell -b '${lib.getExe pkgs.lazy-tmux} daemon >/dev/null 2>&1 || true'

          # Saved-session picker (includes sessions that are not running).
          # M-o is deliberately left unbound in tmux so it falls through to
          # the zsh `^[o` → nvim binding (modules/shell.nix settings).
          bind -n M-i display-popup -B -w 70% -h 75% -E '${lib.getExe pkgs.lazy-tmux} picker'
        '';
      };
    };
}
