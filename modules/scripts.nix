# bin/stb-install and bin/stb-install-nixos stay real files: they run from a
# bare checkout before Nix exists.
_: {
  # Exposed via `stubbe.lib` so the tmux-session check and the installed bins
  # are built from the same bytes.
  stubbe.lib.tmuxLaunchers = {
    "tmux-pick-session" = ''

      # Live sessions, then snapshots of sessions that are not running. The old
      # live-only version was a dead end after a reboot: nothing is live, so it
      # cleared the screen and exited. Selecting a sleeping session wakes it from its
      # snapshot (windows, layouts, pane commands, scrollback, `claude --resume`).
      #
      # `--lines` prints the rows and exits — fzf's ctrl-x reload calls back into it.

      DATA_DIR="''${LAZY_TMUX_DATA_DIR:-$HOME/.local/share/lazy-tmux}"
      # Absolute path to this script: fzf's ctrl-x reload re-runs it for fresh rows.
      SELF=''${0:A}

      # name -> the session's working directory (first pane of its first window).
      # Snapshots outlive the directory they describe: every deleted worktree leaves
      # one behind, and waking it lands in a cwd that no longer exists.
      typeset -A SNAPSHOT_PATH
      snapshot_paths() {
        [[ -d $DATA_DIR/sessions ]] || return 0
        command -v jq >/dev/null 2>&1 || return 0
        jq -r '[.session_name, ([.windows[].panes[].current_path] | first // "")] | @tsv' \
          "$DATA_DIR"/sessions/*.json 2>/dev/null
      }

      # Sessions are named "$(whoami)(repo)" — the prefix is on every row, so it is
      # noise in the list. Strip it for display only; field 1 keeps the real name.
      label_of() {
        local name="$1" user="''${USER:-$(whoami)}"
        if [[ $name == "$user("*")" ]]; then
          name=''${name#"$user("}
          name=''${name%")"}
        fi
        print -r -- "$name"
      }

      # Each row is "<name>\t<display>", and fzf is told to render from field 2 on, so
      # the raw session name survives the render untouched.
      picker_lines() {
        # `cwd`, not `path`: zsh ties the `path` array to $PATH, so a `local path`
        # here would blank PATH for the whole function and every lookup would fail.
        local live name ts size cwd
        # `tmux list-sessions` exits non-zero (and prints to stderr) when no server
        # is running. We can't pre-check with `pgrep tmux`: it matches by truncated
        # comm name (15 chars), and this script's own comm is `tmux-pick-sessi`,
        # which substring-matches "tmux".
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
          # Directory gone (deleted worktree, moved repo): hide the row. ctrl-x in
          # the picker is the way to drop such snapshots for good.
          cwd="''${SNAPSHOT_PATH[$name]}"
          [[ -n $cwd && ! -d $cwd ]] && continue
          # Timestamp trimmed to the minute; the seconds and offset just add noise.
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

      # Sleeping session: restore it before attaching. @pinned comes back through the
      # client-attached hook in tmux.conf.
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

      if command -v direnv >/dev/null 2>&1; then
        # Backgrounded so the tmux switch is never blocked. The new session's
        # first precmd fires direnv's hook; by then `direnv allow` has run
        # and the .env vars are available. Fast path (well-formed .envrc)
        # just re-allows; cold path defers to `denv on` so logic stays
        # single-sourced in the zsh funcs (modules/shell.nix).
        # Only touch denv-authored .envrc files. A hand-written .envrc with no
        # dotenv markers is the user's own — direnv allow / denv on would either
        # be a no-op or actively rewrite it. Skip when no .envrc exists at all.
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
      # `tmux has-session -t=` exact-matches the name, and fails outright when no
      # server is running — either branch below then starts one. pgrep tmux is no
      # use as a server check: it substring-matches our own comm (`tmux-pick-proje`,
      # truncated to 15 chars) and would race against tmux start-up.
      if ! tmux has-session -t="$TMUXCLIENTNAME" 2>/dev/null; then
        # Bring back this repo's last snapshot: window names, layouts, pane
        # commands, shell scrollback, and `claude --resume <id>` for claude panes.
        # Non-zero exit means there is no snapshot yet — the cold-start path.
        # @pinned is replayed by the client-attached hook in tmux.conf, which fires
        # on the attach/switch below.
        if ! lazy-tmux wakeup --session "$TMUXCLIENTNAME" >/dev/null 2>&1; then
          tmux new-session -ds "$TMUXCLIENTNAME" -c "$SELECTED"
          tmux set-option -t "$TMUXCLIENTNAME" @stubbe_has_git 1
        fi
      fi

      if [[ -n $TMUX ]]; then
        tmux switch-client -t "$TMUXCLIENTNAME"
      else
        tmux attach-session -t "$TMUXCLIENTNAME"
      fi
    '';
    "tmux-new-session" = ''

      if [ -z "$1" ]; then
        TMUXCLIENTNAME="$(whoami)(''${''${PWD:t}//./_})"
      else
        TMUXCLIENTNAME="$1"
      fi
      # Wake the snapshot first when the session is not running, so `new -As` below
      # attaches to a restored session instead of an empty one. Non-zero exit means
      # there is nothing saved under that name — then `new -As` creates it.
      if ! tmux has-session -t="$TMUXCLIENTNAME" 2>/dev/null; then
        lazy-tmux wakeup --session "$TMUXCLIENTNAME" >/dev/null 2>&1
      fi

      tmux new -As "$TMUXCLIENTNAME"
    '';
  };

  flake.modules.homeManager.scripts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Defined in modules/core/lib.nix so this wrapper and the zsh completion
      # in modules/shell.nix cannot disagree.
      hmSpec = pkgs.stubbe.hm;

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
            # Escape double quotes and backslashes for awk
            ESCAPED_PATTERN="''${pattern//\\/\\\\}"
            ESCAPED_PATTERN="''${ESCAPED_PATTERN//\"/\\\"}"
            if [[ -n "$AWK_FILTER" ]]; then
              AWK_FILTER="$AWK_FILTER && "
            fi
            AWK_FILTER="$AWK_FILTER index(tolower(\$0), tolower(\"$ESCAPED_PATTERN\")) == 0"
          done

          # Git repos under HOME (outputs absolute paths)
          home_results() {
            fd . \
              --base-directory ~ \
              -t d \
              --max-depth 5 \
              --min-depth 1 \
              --hidden 2>/dev/null \
              | awk -v home="$HOME" '!/^\./ && /\/\.git/ { sub(/\/\.git.*/, ""); if (!seen[$0]++) print home "/" $0 }'
          }

          # Git repos under /etc/nixos — dotfiles live at /etc/nixos/dotfiles on NixOS
          nixos_results() {
            [[ -d /etc/nixos ]] || return 0
            fd . \
              --base-directory /etc/nixos \
              -t d \
              --max-depth 3 \
              --min-depth 1 \
              --hidden 2>/dev/null \
              | awk '/\/\.git/ { sub(/\/\.git.*/, ""); if (!seen[$0]++) print "/etc/nixos/" $0 }'
            # /etc/nixos itself might also be a git repo
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

          # Outside a git repo: clear and exit (the keybinding fires regardless of dir).
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

          # exec so the TUI owns the pane. As a child of this wrapper it shares
          # the wrapper's process group, so #{pane_current_command} reads "zsh"
          # — which makes tmux's toggle_window think the pane fell back to a
          # bare shell and respawn it, restarting btop and losing its graphs.
          # remain-on-exit is off, so the pane still closes when the TUI quits.
          exec "$monitor"
        '';
      };

      launcherBins = lib.mapAttrsToList (name: text: pkgs.stubbe.zshApp { inherit name text; }) launchers;

      clip = pkgs.stubbe.bashApp {
        name = "clip";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          # Copy stdin (or the arguments) to the system clipboard from wherever
          # this shell happens to be: a local Wayland or X11 session, macOS,
          # inside tmux, or over SSH on a box with no display at all.
          #
          # The sink order matters more than the sink list. Over SSH a $DISPLAY
          # or $WAYLAND_DISPLAY inherited from the *remote* box's own session is
          # a trap: writing there copies to a machine nobody is looking at, and
          # reports success. So on a remote host the terminal-side sinks (tmux,
          # OSC 52) go first and the display sinks are the last resort; on a
          # local host it is the other way round.

          data=$(if [ "$#" -gt 0 ]; then printf '%s' "$*"; else cat; fi)
          [ -n "$data" ] || exit 0

          # tmux's own paste buffer is not one of the sinks below: it is free, it
          # cannot fail, and it makes `prefix ]` work whichever sink ends up
          # winning. -w is deliberately absent here — that is sink_tmux's job.
          if [ -n "''${TMUX:-}" ]; then
            printf '%s' "$data" | tmux load-buffer - 2>/dev/null || true
          fi

          sink_wayland() {
            [ -n "''${WAYLAND_DISPLAY:-}" ] || return 1
            command -v wl-copy >/dev/null 2>&1 || return 1
            printf '%s' "$data" | wl-copy
          }

          sink_x11() {
            [ -n "''${DISPLAY:-}" ] || return 1
            if command -v xclip >/dev/null 2>&1; then
              printf '%s' "$data" | xclip -selection clipboard
            elif command -v xsel >/dev/null 2>&1; then
              printf '%s' "$data" | xsel --clipboard --input
            else
              return 1
            fi
          }

          sink_macos() {
            command -v pbcopy >/dev/null 2>&1 || return 1
            printf '%s' "$data" | pbcopy
          }

          # tmux >= 3.2: -w forwards the buffer to the *outer* terminal as an
          # OSC 52 write, which is what carries the copy back across an SSH hop.
          # Older tmux has no -w and fails here; sink_osc52 then does it by hand.
          sink_tmux() {
            [ -n "''${TMUX:-}" ] || return 1
            printf '%s' "$data" | tmux load-buffer -w - 2>/dev/null
          }

          # The only sink that needs nothing but a terminal: ask the emulator
          # itself to set the clipboard. Survives any number of SSH hops because
          # the escape rides the same stream as the text.
          sink_osc52() {
            # 100 KiB is xterm's default selection limit and far past anything a
            # path picker produces. Truncating would copy a corrupt value that
            # still looks plausible, so refuse and let another sink answer.
            [ "''${#data}" -le 102400 ] || return 1
            local b64 seq
            b64=$(printf '%s' "$data" | base64 | tr -d '\n')
            seq="\033]52;c;$b64\a"
            if [ -n "''${TMUX:-}" ]; then
              # DCS passthrough (needs `allow-passthrough on`, set in
              # modules/tmux.nix): tmux hands the inner sequence to the outer
              # terminal. Every ESC inside the wrapper has to be doubled, hence
              # the \033\033 after `tmux;`.
              seq="\033Ptmux;\033$seq\033\\"
            fi
            # /dev/tty exists and stats as writable even with no controlling
            # terminal (cron, a systemd unit, a detached pipeline) — it is the
            # *open* that fails, with ENXIO. So probe it by opening, and put the
            # stderr redirect first so the failed open is silent rather than a
            # stray shell message on an otherwise clean fallback.
            printf '%b' "$seq" 2>/dev/null >/dev/tty
          }

          if [ -n "''${SSH_CONNECTION:-}" ] || [ -n "''${SSH_TTY:-}" ]; then
            sinks=(sink_tmux sink_osc52 sink_wayland sink_x11 sink_macos)
          else
            sinks=(sink_wayland sink_x11 sink_macos sink_tmux sink_osc52)
          fi

          for sink in "''${sinks[@]}"; do
            if "$sink"; then
              exit 0
            fi
          done

          echo "clip: no clipboard reachable (no Wayland/X11/pbcopy, no tmux, no writable /dev/tty)" >&2
          exit 1
        '';
      };

      # Absolute store paths so the wrapper never depends on PATH.
      hm = pkgs.stubbe.bashApp {
        name = "hm";
        text = ''
          # Personal home-manager / nixos-rebuild front-end.
          set -euo pipefail

          hm_flake_dir="''${HM_FLAKE_DIR:-${config.stubbe.paths.dotfiles}}"

          has_cmd() {
            command -v "$1" >/dev/null 2>&1
          }

          if has_cmd readlink; then
            hm_flake_dir=$(readlink -f "$hm_flake_dir" 2>/dev/null || echo "$hm_flake_dir")
          fi

          hm_flake_ref="path:$hm_flake_dir"

          # On NixOS the home-manager CLI isn't installed (submoduleSupport
          # path in upstream programs/home-manager.nix gates `home.packages`
          # on `!submoduleSupport.enable`), so switch/build shell out to
          # nixos-rebuild against nixosConfigurations.<hostname>. Override
          # the resolved attr with HM_NIXOS_CONFIG if the flake key differs.
          is_nixos() {
            [ -r /etc/os-release ] && grep -q '^ID=nixos' /etc/os-release
          }

          nixos_attr() {
            echo "''${HM_NIXOS_CONFIG:-$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)}"
          }

          # --- nh delegation -------------------------------------------------------
          # nh (nix-community/nh) wraps nixos-rebuild / home-manager with a version
          # diff (nvd) and nix-output-monitor progress. It ships unconditionally
          # alongside this script (modules/scripts.nix), so the build/activate
          # verbs always route through it; the verbs nh doesn't cover (dry-*,
          # build-vm*, news, instantiate) stay on the raw path below. nh self-elevates
          # on NixOS, so these calls carry no sudo prefix.
          run_nh() {
            local subcmd="$1"; shift
            local sub=home ref="$hm_flake_ref"
            if is_nixos; then
              sub=os
              # nh derives the host attr from `hostname` just like nixos_attr's
              # default; only pin it explicitly when HM_NIXOS_CONFIG overrides.
              [ -n "''${HM_NIXOS_CONFIG:-}" ] && ref="$ref#$HM_NIXOS_CONFIG"
            fi
            nh "$sub" "$subcmd" "$ref" -- --impure "$@"
          }

          run_hm_subcmd() {
            local subcmd="$1"; shift

            # Fast path: verbs nh renders with a version diff. boot/test are
            # NixOS-only. Remaining verbs (dry-*, build-vm*, news, instantiate,
            # passthrough) fall through to the raw path below.
            case "$subcmd" in
              switch|boot|test|build|repl)
                if ! is_nixos; then
                  case "$subcmd" in
                    boot|test)
                      echo "hm $subcmd: NixOS-only (no home-manager CLI equivalent)." >&2
                      return 1
                      ;;
                  esac
                fi
                run_nh "$subcmd" "$@"
                return
                ;;
            esac

            if is_nixos; then
              # Only the verbs nh doesn't cover reach here. None activate the
              # system (switch/boot/test are handled by the nh fast path), so
              # there's no privileged write and no HM activation to replay —
              # except dry-activate, which runs the activation script in dry mode.
              local prefix=()
              case "$subcmd" in
                dry-activate)
                  prefix=(sudo)
                  ;;
                dry-build|build-vm|build-vm-with-bootloader)
                  ;;
                *)
                  echo "hm $subcmd: unavailable on NixOS. Supported subcommands: ${hmSpec.nixosVerbs}." >&2
                  return 1
                  ;;
              esac
              "''${prefix[@]}" nixos-rebuild "$subcmd" --flake "$hm_flake_ref#$(nixos_attr)" --impure "$@"
            else
              case "$subcmd" in
                # nixos-rebuild-only verbs — no home-manager equivalent.
                boot|test|dry-activate|dry-build|build-vm|build-vm-with-bootloader|repl)
                  echo "hm $subcmd: NixOS-only (no home-manager CLI equivalent)." >&2
                  return 1
                  ;;
                *)
                  home-manager "$subcmd" --flake "$hm_flake_ref" --impure "$@"
                  ;;
              esac
            fi
          }

          run_rollback() {
            if is_nixos; then
              nh os rollback "$@"
            else
              echo "hm rollback: not implemented for standalone home-manager. Use 'home-manager generations' to list, then run '<gen>/activate' from the desired generation." >&2
              return 2
            fi
          }

          run_gc() {
            # No args: hand off to `nh clean` (all profiles + gcroots + store gc,
            # with a summary). With explicit args the caller is speaking
            # nix-collect-garbage's flag language (-d, --delete-older-than …), which
            # nh clean doesn't share, so pass them to nix-collect-garbage verbatim.
            if [ "$#" -eq 0 ]; then
              if is_nixos; then
                nh clean all
              else
                nh clean user
              fi
              return
            fi

            if is_nixos; then
              # sudo so the system profile is also collected, not just the
              # invoking user's. nix-collect-garbage scopes by who runs it.
              sudo nix-collect-garbage "$@"
            else
              nix-collect-garbage "$@"
            fi
          }

          run_generations() {
            if is_nixos; then
              # nh os info lists the system profile generations as a table.
              nh os info "$@"
            else
              home-manager generations "$@"
            fi
          }

          # Generation trimming on every switch is handled by activation hooks, not
          # here: modules/nix.nix (system.activationScripts.pruneSystemGenerations)
          # and modules/nix.nix (home.activation.pruneNixGenerations) both trim
          # profiles to "current + 1 previous" as part of the switch. Store GC runs on
          # the weekly nix.gc / nix-collect-garbage timers. So `hm switch`/`upgrade`
          # need do nothing extra — for an immediate store sweep, run `hm gc`.

          ensure_sudo() {
            if [[ "''${1:-}" == "true" ]]; then
              echo "Requesting sudo..."
              sudo -v
            fi
          }

          # On NixOS the activate verbs self-sudo deep inside nixos-rebuild, so the
          # password prompt only appears after inputs are updated and the build runs.
          # Prime the sudo timestamp upfront so `switch`/`upgrade` prompt immediately.
          prime_sudo_nixos() {
            if is_nixos && has_cmd sudo; then
              echo "Requesting sudo..."
              sudo -v
            fi
          }

          # --- flake.lock git automation -------------------------------------------
          # `hm update`/`upgrade` regenerate flake.lock; keep it committed and synced
          # with the remote without ever stopping on a merge conflict. flake.lock is
          # fully generated, so a merge driver that keeps the in-progress side ("true"
          # = exit 0, take current) makes every rebase/pull non-interactive; we then
          # re-run `nix flake update` so the newest input revs land on top.
          flake_git() {
            git -C "$hm_flake_dir" "$@"
          }

          flake_in_git() {
            has_cmd git && flake_git rev-parse --is-inside-work-tree >/dev/null 2>&1
          }

          flake_has_upstream() {
            flake_git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1
          }

          # Register the flake.lock merge driver locally. Idempotent; .git/config is
          # untracked so it can't ship via the repo. .gitattributes maps
          # `flake.lock merge=flakelock` onto this driver.
          ensure_flakelock_driver() {
            flake_git config merge.flakelock.name "keep current flake.lock (regenerated)" >/dev/null 2>&1 || true
            flake_git config merge.flakelock.driver true >/dev/null 2>&1 || true
          }

          # Absorb remote commits before regenerating so the new lock lands on top of
          # whatever other hosts already pushed. --autostash protects unrelated dirty
          # work; the merge driver keeps it conflict-free.
          sync_flake_repo() {
            flake_in_git || return 0
            flake_has_upstream || return 0
            flake_git fetch --quiet || return 0
            flake_git pull --rebase --autostash --quiet || {
              flake_git rebase --abort >/dev/null 2>&1 || true
            }
          }

          # Commit flake.lock iff it changed, then push. A push race (remote moved
          # between our pull and push) is retried once after another rebase — again
          # conflict-free via the merge driver.
          commit_flake_lock() {
            flake_in_git || return 0
            flake_git diff --quiet -- flake.lock 2>/dev/null && return 0   # unchanged
            flake_git add -- flake.lock || return 0
            flake_git commit -m "chore: update flake.lock" -- flake.lock >/dev/null || return 0
            echo "Committed updated flake.lock"
            flake_has_upstream || return 0
            flake_git push --quiet 2>/dev/null && return 0
            flake_git pull --rebase --autostash --quiet || {
              flake_git rebase --abort >/dev/null 2>&1 || true
              echo "flake.lock committed locally; push failed (resolve manually)" >&2
              return 0
            }
            flake_git push --quiet 2>/dev/null || \
              echo "flake.lock committed locally; push failed (resolve manually)" >&2
          }

          # --- push freshly-built closure to the binary cache ----------------------
          # After a switch, upload what THIS machine compiled to nix.stubbe.dev so other
          # machines substitute it instead of rebuilding (replaces the retired nightly
          # prebuild CI job). Best-effort: a push failure must never fail the switch.
          push_to_cache() {
            # ${lib.getExe' pkgs.xilo "xilo"} is templated to an absolute store path; skip if unavailable.
            has_cmd ${lib.getExe' pkgs.xilo "xilo"} || return 0

            local tokenFile="$hm_flake_dir/secrets/xilo-token"
            if [ ! -f "$tokenFile" ]; then
              echo "cache push: secrets/xilo-token missing — run 'hm secret set xilo-token'. Skipping." >&2
              return 0
            fi

            # Decrypt the push token with the age identity derived from the SSH key —
            # the same path sops-nix uses, so it doesn't depend on a materialised
            # ~/.config/sops/age/keys.txt.
            local ageKey token
            ageKey=$(${lib.getExe pkgs.ssh-to-age} -private-key -i "$HOME/.ssh/id_ed25519" 2>/dev/null) || return 0
            token=$(SOPS_AGE_KEY="$ageKey" ${lib.getExe pkgs.sops} --decrypt \
              --input-type binary --output-type binary "$tokenFile" 2>/dev/null) || {
              echo "cache push: could not decrypt xilo-token; skipping." >&2
              return 0
            }

            # What we just activated. `xilo push` uploads the full closure but skips
            # paths the server already has and anything signed by cache.nixos.org, so
            # only the first-party deltas actually transfer. `default` resolves to the
            # default/default cache under xilo's namespacing.
            local path
            if is_nixos; then
              path=$(readlink -f /run/current-system 2>/dev/null)
            else
              path=$(readlink -f "$HOME/.local/state/nix/profiles/home-manager" 2>/dev/null)
            fi
            [ -n "$path" ] && [ -e "$path" ] || return 0

            echo "Pushing $(basename "$path") closure to the cache…"
            XILO_URL="https://nix.stubbe.dev" XILO_TOKEN="$token" \
              ${lib.getExe' pkgs.xilo "xilo"} push default "$path" --quiet \
              || echo "cache push failed (non-fatal)." >&2
          }

          # Some inputs are pinned to a release tag in flake.nix (tracking master
          # rebuilds on every upstream commit). Move each pin to the latest GitHub
          # release before `nix flake update` so the new tags are locked in the same
          # pass. Best-effort: offline / API failure keeps the current pin.
          release_pinned_repos="PHPantom-dev/phpantom_lsp"
          bump_release_pins() {
            local repo latest name bumped=""
            has_cmd curl || return 0
            for repo in $release_pinned_repos; do
              # `|| true`: grep -m1 exits at the first match and closes the pipe while
              # curl is still writing — curl then fails (23) and pipefail + set -e would
              # kill the whole script silently. Empty $latest is handled below.
              latest=$(curl -fsSL --max-time 10 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
                | grep -om1 '"tag_name": *"[^"]*"' | cut -d'"' -f4) || true
              [ -n "$latest" ] || continue
              grep -q "github:$repo/$latest" "$hm_flake_dir/flake.nix" && continue
              sed -i "s|github:$repo/[^\"]*|github:$repo/$latest|" "$hm_flake_dir/flake.nix"
              name=''${repo##*/}
              echo "Bumped $name pin to $latest"
              bumped="$bumped $name→$latest"
            done
            [ -n "$bumped" ] || return 0
            if flake_in_git; then
              flake_git add -- flake.nix >/dev/null 2>&1 || return 0
              flake_git commit -qm "chore: bump release pins:$bumped" -- flake.nix >/dev/null 2>&1 || true
            fi
          }

          update_system() {
            local needs_sudo="false"

            if has_cmd pacman || has_cmd apt || has_cmd dnf || has_cmd snap; then
              needs_sudo="true"
            fi

            ensure_sudo "$needs_sudo"

            if has_cmd pacman; then
              echo "Updating pacman packages"
              sudo pacman -Syu --noconfirm
            fi

            if has_cmd apt; then
              echo "Updating apt packages"
              # -qq: errors only — drops the Hit lines, Ubuntu Pro/ESM nag, phasing
              # notice, and the per-command Summary blocks. apt-get (not apt) is the
              # stable scripting interface. noninteractive skips needrestart prompts.
              sudo apt-get -qq update
              sudo DEBIAN_FRONTEND=noninteractive apt-get -qq -y upgrade
              sudo apt-get -qq -y autoremove
            fi

            if has_cmd dnf; then
              echo "Updating dnf packages"
              sudo dnf upgrade -y
            fi

            if has_cmd snap; then
              echo "Updating snap packages"
              sudo snap refresh
            fi

            if has_cmd flatpak; then
              echo "Updating flatpak packages"
              flatpak update -y
              flatpak uninstall --unused -y
            fi

            if has_cmd nix; then
              echo "Updating nix inputs"
              if flake_in_git; then
                ensure_flakelock_driver
                sync_flake_repo
              fi
              bump_release_pins
              # --quiet drops the per-input "copying path …" spam; warnings/errors
              # still surface. The nh switch afterwards shows the actual version diff.
              nix flake update --flake "$hm_flake_ref" --quiet
              commit_flake_lock
            fi

            if has_cmd nix-channel; then
              # Vestigial on a flakes host; silence the "unpacking N channels…" line.
              nix-channel --update >/dev/null 2>&1 || true
            fi
          }

          usage() {
            cat <<'EOF'
          Usage: hm <command> [args]

          Commands:
          ${hmSpec.renderExpandedHelp "wrapper"}

          ${hmSpec.renderExpandedHelp "rebuild"}
          ${hmSpec.renderHelp "meta"}

          switch/boot/test/build/repl, gc, generations, and rollback route through
          `nh` (version diff + progress output). The remaining verbs (dry-build,
          dry-activate, build-vm*, news, instantiate) use raw nixos-rebuild/home-manager.

          On NixOS the build/activate verbs delegate to `[sudo ]nixos-rebuild
          <cmd> --flake <flake>#<host> --impure`. The host attr defaults to
          `hostname -s`; override with HM_NIXOS_CONFIG=<attr>. Verbs without
          a NixOS counterpart (news/instantiate) error on NixOS; verbs without
          a home-manager counterpart (boot/test/dry-activate/dry-build/build-vm
          /repl) error on non-NixOS. Unknown args fall through to home-manager
          on non-NixOS.
          EOF
          }

          hm_whoami() {
            if [ ! -f "$HOME/.ssh/id_ed25519.pub" ]; then
              echo "hm whoami: ~/.ssh/id_ed25519.pub not found" >&2
              return 1
            fi
            local pubkey host
            pubkey=$(${lib.getExe pkgs.ssh-to-age} < "$HOME/.ssh/id_ed25519.pub")
            host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")
            printf '%s %s\n' "$host" "$pubkey"
          }

          hm_trust() {
            local name="" pubkey=""

            # Resolve (name, pubkey) from one of three forms:
            #   1) hm trust <name> <pubkey>            — explicit
            #   2) hm trust <pubkey>                   — auto-name
            #   3) cmd | hm trust                      — stdin "<name> <pubkey>" or "<pubkey>"
            if [ "$#" -ge 2 ]; then
              name="$1"; pubkey="$2"
            elif [ "$#" -eq 1 ]; then
              pubkey="$1"
            elif [ "$#" -eq 0 ] && [ ! -t 0 ]; then
              local line
              if ! IFS= read -r line || [ -z "$line" ]; then
                echo "hm trust: empty stdin (expected '<name> <pubkey>' or '<pubkey>')" >&2
                return 2
              fi
              # shellcheck disable=SC2086
              set -- $line
              if [ "$#" -ge 2 ]; then
                name="$1"; pubkey="$2"
              else
                pubkey="$1"
              fi
            else
              cat <<EOF >&2
          Usage:
            hm trust <name> <pubkey>      # explicit
            hm trust <pubkey>             # auto-name from hostname or pubkey suffix
            <cmd> | hm trust              # e.g. ssh laptop2 hm whoami | hm trust
          EOF
              return 2
            fi

            # Auto-derive name if not supplied. Prefer the local hostname when
            # the pubkey is *this machine's* SSH-derived recipient; otherwise
            # fall back to the pubkey's last 8 chars so the line is at least
            # eyeball-distinguishable.
            if [ -z "$name" ]; then
              local local_pubkey=""
              if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
                local_pubkey=$(${lib.getExe pkgs.ssh-to-age} < "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || true)
              fi
              if [ -n "$local_pubkey" ] && [ "$pubkey" = "$local_pubkey" ]; then
                name=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")
              else
                name="''${pubkey: -8}"
              fi
            fi

            if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
              echo "hm trust: derived name '$name' must match [A-Za-z0-9_-]+" >&2
              return 2
            fi

            # Validate the bech32-encoded age pubkey by attempting an
            # encryption with it. age fails fast on a bad checksum, so we
            # don't mutate .sops.yaml on bad input.
            if ! ${lib.getExe pkgs.age} -r "$pubkey" -o /dev/null </dev/null 2>/dev/null; then
              echo "hm trust: '$pubkey' is not a valid age recipient pubkey" >&2
              return 2
            fi

            local sops_yaml="$hm_flake_dir/.sops.yaml"
            if [ ! -f "$sops_yaml" ]; then
              echo "hm trust: $sops_yaml not found" >&2
              return 1
            fi

            if grep -qF "$pubkey" "$sops_yaml"; then
              echo "hm trust: $pubkey already present in .sops.yaml — nothing to do."
              return 0
            fi

            # Snapshot for rollback if any sops updatekeys call fails.
            local backup
            backup=$(mktemp)
            cp "$sops_yaml" "$backup"

            rollback() {
              cp "$backup" "$sops_yaml"
              rm -f "$backup"
              echo "hm trust: rolled back .sops.yaml" >&2
            }

            # Append the new recipient line directly after the last existing
            # 'age1...' entry under the age list. Awk preserves comments and
            # surrounding structure, unlike a YAML round-trip.
            local tmp
            tmp=$(mktemp)
            awk -v new="          - $pubkey  # $name" '
              /^          - age1/ { last = NR }
              { lines[NR] = $0 }
              END {
                for (i = 1; i <= NR; i++) {
                  print lines[i]
                  if (i == last) print new
                }
              }
            ' "$sops_yaml" > "$tmp"
            mv "$tmp" "$sops_yaml"

            echo "Added $name → $pubkey to .sops.yaml"

            # Re-wrap each existing secrets file's data key for the new recipient.
            # Any failure rolls .sops.yaml back so the repo isn't left half-edited.
            shopt -s nullglob
            local secret count=0
            for secret in "$hm_flake_dir"/secrets/*; do
              [ -f "$secret" ] || continue
              echo "Re-wrapping $(basename "$secret")"
              if ! ${lib.getExe pkgs.sops} updatekeys --yes "$secret"; then
                rollback
                return 1
              fi
              count=$((count + 1))
            done
            rm -f "$backup"

            cat <<MSG

          Trusted $name across $count secret file(s).
          Review:  git -C "$hm_flake_dir" diff -- .sops.yaml secrets/
          Commit:  git -C "$hm_flake_dir" add .sops.yaml secrets/ && \\
                   git -C "$hm_flake_dir" commit -m "trust: add $name age recipient"
          MSG
          }

          hm_cache() {
            local target="''${1:-}"
            case "$target" in
              nvim)
                echo "Clearing nvim cache (~/.local/{share,state}/nvim and ~/.cache/nvim)..."
                rm -rf \
                  "$HOME/.local/share/nvim" \
                  "$HOME/.local/state/nvim" \
                  "$HOME/.cache/nvim"
                ;;
              locks)
                # Privileged activations (modules/core/setup.nix) skip
                # themselves on each switch when their lock file matches the action
                # hash + state-input hash. Wiping the lock files forces every gated
                # activation to re-run on the next switch — useful when
                # a system file has drifted out from under us (manual edit, package
                # upgrade clobber, …) and we want home-manager to reassert the
                # managed copy. See modules/core/setup.nix (sudoScript).
                local lock_dir="$HOME/.local/state/nix/home-manager"
                if [ -d "$lock_dir" ]; then
                  local count
                  count=$(find "$lock_dir" -maxdepth 1 -name '*.lock.sum' -type f | wc -l)
                  if [ "$count" -gt 0 ]; then
                    echo "Wiping $count activation lock(s) at $lock_dir..."
                    find "$lock_dir" -maxdepth 1 -name '*.lock.sum' -type f -delete
                  else
                    echo "No activation locks under $lock_dir; nothing to do."
                  fi
                else
                  echo "$lock_dir does not exist; nothing to do."
                fi
                echo "Next 'hm switch' will re-run each privileged activation."
                ;;
              all)
                hm_cache nvim
                ;;
              ""|-h|--help)
                cat <<EOF >&2
          Usage: hm cache <target>

          Targets:
          ${hmSpec.renderSubHelp "cache"}
          EOF
                [ -z "$target" ] && return 2 || return 0
                ;;
              *)
                echo "hm cache: unknown target '$target' (want ${hmSpec.subNames "cache"})" >&2
                return 2
                ;;
            esac
          }

          hm_clean() {
            local root="''${1:-$HOME}"
            has_cmd fzf || { echo "hm clean: fzf not found" >&2; return 1; }

            echo "Scanning $root for reclaimable space (build artifacts, caches, core dumps)..." >&2

            local -a paths=()
            # Regenerable build/dependency dirs — match once, don't descend into them.
            while IFS= read -r -d ''' p; do paths+=("$p"); done < <(
              find "$root" -xdev \( -path '*/.git' -o -path "$HOME/.cache" \) -prune -o \
                \( -name node_modules -o -name target -o -name .next -o -name dist -o -name vendor -o -name .venv \) \
                -type d -print0 -prune 2>/dev/null
            )
            # Crash dumps directly under $HOME.
            while IFS= read -r -d ''' p; do paths+=("$p"); done < <(
              find "$HOME" -maxdepth 1 \( -name 'core.[0-9]*' -o -name 'core' \) -type f -print0 2>/dev/null
            )
            # Cache subdirectories.
            while IFS= read -r -d ''' p; do paths+=("$p"); done < <(
              find "$HOME/.cache" -mindepth 1 -maxdepth 1 -print0 2>/dev/null
            )

            local -a menu=($'(action)\tNix store garbage — old generations + unreachable paths (runs: hm gc)')
            if [ "''${#paths[@]}" -gt 0 ]; then
              while IFS= read -r line; do menu+=("$line"); done < <(
                du -sh -- "''${paths[@]}" 2>/dev/null | sort -rh
              )
            fi

            local selection
            selection=$(printf '%s\n' "''${menu[@]}" | fzf --multi \
              --header='TAB select, ENTER to review & delete. Regenerable build dirs, caches, core dumps, nix gc.' \
              --delimiter=$'\t' --with-nth=1,2)
            [ -n "$selection" ] || { echo "hm clean: nothing selected"; return 0; }

            echo
            echo "About to remove:"
            echo "$selection" | sed 's/^/  /'
            read -rp "Proceed? [y/N] " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { echo "hm clean: aborted"; return 0; }

            local size target
            while IFS=$'\t' read -r size target; do
              if [ "$size" = "(action)" ]; then
                run_gc
                continue
              fi
              echo "Removing $target ($size)..."
              rm -rf -- "$target"
            done <<< "$selection"

            echo "Done."
          }

          hm_secret() {
            local action="''${1:-}"
            local name="''${2:-}"
            if [ -z "$action" ] || [ -z "$name" ]; then
              echo "Usage: hm secret {${hmSpec.subNames "secret"}} <name>" >&2
              return 2
            fi
            # All secrets are binary-mode single-blob files under secrets/<name>.
            local path="$hm_flake_dir/secrets/$name"
            case "$action" in
              edit)
                # sops handles both create and edit transparently. Pass binary
                # input/output types so creating a new secret opens an empty
                # buffer (no yaml starter template).
                ${lib.getExe pkgs.sops} --input-type binary --output-type binary "$path"
                ;;
              set)
                # Replace the secret value without opening an editor. On a TTY
                # we prompt twice and confirm; piped input goes straight in
                # (e.g. `secret-tool lookup ... | hm secret set vpn-konform`).
                local pw=""
                if [ -t 0 ]; then
                  read -srp "New value for $name: " pw
                  echo
                  local pw2=""
                  read -srp "Confirm: " pw2
                  echo
                  if [ "$pw" != "$pw2" ]; then
                    echo "hm secret set: values do not match" >&2
                    return 1
                  fi
                  unset pw2
                else
                  pw=$(cat)
                fi
                if [ -z "$pw" ]; then
                  echo "hm secret set: refusing to write empty value" >&2
                  return 1
                fi
                # --filename-override makes sops apply the creation_rules for
                # secrets/<name> even though stdin doesn't have a real path.
                # Write to a sibling tmp file then rename so a failure mid-
                # encrypt can't truncate the existing secret.
                local tmp="$path.new"
                if ! printf '%s' "$pw" | ${lib.getExe pkgs.sops} --encrypt \
                    --input-type binary --output-type binary \
                    --filename-override "$path" /dev/stdin > "$tmp"; then
                  rm -f "$tmp"
                  unset pw
                  echo "hm secret set: encryption failed" >&2
                  return 1
                fi
                mv "$tmp" "$path"
                unset pw
                echo "Updated secrets/$name. Run 'hm switch' to deploy, then commit."
                ;;
              rotate)
                if [ ! -f "$path" ]; then
                  echo "hm secret rotate: $path does not exist" >&2
                  return 1
                fi
                ${lib.getExe pkgs.sops} --rotate -i \
                  --input-type binary --output-type binary "$path"
                echo "Re-rolled data key for $name. Recipients unchanged."
                ;;
              *)
                echo "hm secret: unknown action '$action' (want edit|set|rotate)" >&2
                return 2
                ;;
            esac
          }

          case "''${1:-}" in
            update)
              shift
              update_system
              ;;
            upgrade)
              shift
              prime_sudo_nixos
              update_system
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              run_hm_subcmd switch "$@" && push_to_cache
              ;;
            whoami)
              shift
              hm_whoami
              ;;
            trust)
              shift
              hm_trust "$@"
              ;;
            secret)
              shift
              hm_secret "$@"
              ;;
            cache)
              shift
              hm_cache "$@"
              ;;
            clean)
              shift
              hm_clean "$@"
              ;;
            iso)
              shift
              nixos-iso "$@"
              ;;
            help|-h|--help)
              usage
              ;;
            switch)
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              shift
              prime_sudo_nixos
              run_hm_subcmd switch "$@" && push_to_cache
              ;;
            boot|test|build|dry-build|dry-activate|build-vm|build-vm-with-bootloader|repl|news|instantiate)
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              subcmd="$1"
              shift
              run_hm_subcmd "$subcmd" "$@"
              ;;
            rollback)
              shift
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              run_rollback "$@"
              ;;
            gc)
              shift
              run_gc "$@"
              ;;
            generations)
              shift
              run_generations "$@"
              ;;
            "")
              # `hm` with no args: show usage rather than tripping `set -u`
              # on `$1` below, or proxying an empty arg to home-manager.
              usage
              exit 2
              ;;
            *)
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              if is_nixos; then
                echo "hm: '$1' is not supported on NixOS — the home-manager CLI is not available in submodule mode. Try 'hm help'." >&2
                exit 2
              fi
              home-manager --impure "$@"
              ;;
          esac
        '';
      };

      nixosIso = pkgs.stubbe.bashApp {
        name = "nixos-iso";
        text = ''
          # Wrapper around `nix build .#installer-iso` + utilities for writing
          # the result to a USB stick.
          set -euo pipefail

          flake_dir="''${NIXOS_FLAKE_DIR:-${config.stubbe.paths.dotfiles}}"
          out_link="''${NIXOS_ISO_OUT_LINK:-''${XDG_CACHE_HOME:-$HOME/.cache}/nixos-installer-iso}"

          has_cmd() {
            command -v "$1" >/dev/null 2>&1
          }

          if has_cmd readlink; then
            flake_dir=$(readlink -f "$flake_dir" 2>/dev/null || echo "$flake_dir")
          fi

          flake_ref="path:$flake_dir"

          usage() {
            cat <<'EOF'
          Usage: nixos-iso <command> [args]

          Commands:
          ${hmSpec.renderSubHelp "iso"}

          Environment:
            NIXOS_FLAKE_DIR       Override the flake directory (default: ~/.stubbe)
            NIXOS_ISO_OUT_LINK    Override the build result link (default: ~/.cache/nixos-installer-iso)

          The ISO build always reads ~/.ssh impurely and embeds detected public
          and private SSH key files into /root/.ssh on the live image.
          EOF
          }

          build_iso() {
            nix build --impure "$flake_ref#installer-iso" --out-link "$out_link" "$@"
          }

          resolve_iso_path() {
            local dir
            dir=$(readlink -f "$out_link")
            echo "$dir"/iso/*.iso
          }

          print_iso_path() {
            build_iso "$@" >/dev/null
            resolve_iso_path
          }

          list_devices() {
            lsblk -d -o NAME,SIZE,MODEL,TRAN,RM,TYPE,MOUNTPOINTS
          }

          burn_iso() {
            local device=""
            local yes="false"
            local nix_args=()

            while [[ "$#" -gt 0 ]]; do
              case "$1" in
                --yes|-y)
                  yes="true"
                  shift
                  ;;
                --)
                  shift
                  nix_args+=("$@")
                  break
                  ;;
                -* )
                  nix_args+=("$1")
                  shift
                  ;;
                *)
                  if [[ -z "$device" ]]; then
                    device="$1"
                  else
                    nix_args+=("$1")
                  fi
                  shift
                  ;;
              esac
            done

            if [[ -z "$device" ]]; then
              usage >&2
              exit 2
            fi

            if [[ ! -b "$device" ]]; then
              echo "Not a block device: $device" >&2
              exit 1
            fi

            case "$device" in
              /dev/sd*|/dev/nvme*n*|/dev/mmcblk*)
                ;;
              *)
                echo "Refusing unexpected device path: $device" >&2
                exit 1
                ;;
            esac

            if [[ "$yes" != "true" ]]; then
              echo "Refusing to write without --yes because this destroys data on $device" >&2
              exit 2
            fi

            if [[ -n "$(lsblk -nr -o MOUNTPOINTS "$device" | tr -d '[:space:]')" ]]; then
              echo "Refusing to write because $device or one of its partitions is mounted" >&2
              exit 1
            fi

            # Skip rebuild if result link already points to a valid store path
            # and no extra nix args were given. This avoids the full --impure
            # re-evaluation (which nix always reruns even when nothing changed)
            # when the user just ran `hm iso build` moments before.
            if [[ "''${#nix_args[@]}" -gt 0 ]] || \
               ! { [[ -L "$out_link" ]] && [[ -e "$(readlink -f "$out_link" 2>/dev/null || true)" ]]; }; then
              build_iso "''${nix_args[@]}"
            else
              echo "Reusing existing ISO build: $(readlink -f "$out_link")"
            fi
            iso_path=$(resolve_iso_path)

            echo "Writing $iso_path to $device"
            iso_size=$(stat -c%s "$iso_path" 2>/dev/null || stat -f%z "$iso_path" 2>/dev/null || echo 0)
            if command -v pv >/dev/null 2>&1 && [[ "$iso_size" -gt 0 ]]; then
              pv -s "$iso_size" "$iso_path" | sudo dd of="$device" bs=16M conv=fsync
            else
              # bs=16M: larger chunks reduce syscall overhead.
              # conv=fsync: single flush at end instead of after every block (oflag=sync).
              sudo dd if="$iso_path" of="$device" bs=16M status=progress conv=fsync
            fi
            sync
          }

          case "''${1:-}" in
            build)
              shift
              build_iso "$@"
              ;;
            path)
              shift
              print_iso_path "$@"
              ;;
            devices)
              shift
              list_devices
              ;;
            burn|write)
              shift
              burn_iso "$@"
              ;;
            help|-h|--help|"")
              usage
              ;;
            *)
              build_iso "$@"
              ;;
          esac
        '';
      };
    in
    {
      home.packages = [
        clip
        hm
        nixosIso
        pkgs.nh
      ]
      ++ lib.optionals config.features.desktop launcherBins;
    };
}
