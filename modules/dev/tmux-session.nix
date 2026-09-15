{ self, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      deployedFiles = self.homeConfigurations.stubbe.config.xdg.configFile;
      tmuxConf = deployedFiles."tmux/tmux.conf".source;
      commandsSh =
        self.homeConfigurations.stubbe.config.home.file.".config/tmux/scripts/commands.sh".source;

      launcherBins = map (
        name:
        pkgs.stubbe.zshApp {
          inherit name;
          text = pkgs.stubbe.tmuxLaunchers.${name};
        }
      ) (builtins.attrNames pkgs.stubbe.tmuxLaunchers);
    in
    {
      checks.tmux-session =
        pkgs.runCommand "check-tmux-session"
          {
            nativeBuildInputs = [
              pkgs.tmux
              pkgs.zsh
              pkgs.git
              pkgs.util-linux
            ];
          }
          ''
            set -euo pipefail

            export HOME="$(mktemp -d)"
            export TMUX_TMPDIR="$(mktemp -d)"
            export XDG_RUNTIME_DIR="$(mktemp -d)"
            export XDG_STATE_HOME="$HOME/.local/state"
            mkdir -p "$HOME/.config/tmux/scripts"

            # commands.sh carries the deployed `#!/usr/bin/env bash` shebang,
            commands="$HOME/.config/tmux/scripts/commands.sh"
            install -m755 ${commandsSh} "$commands"
            mkdir -p "$HOME/bin"
            install -m755 ${lib.concatMapStringsSep " " (b: "${b}/bin/*") launcherBins} "$HOME/bin/"

            repo="$HOME/repo"
            mkdir -p "$repo"
            cat > "$HOME/bin/fzf-pick-project" <<EOF
            #!/bin/sh
            echo "$repo"
            EOF
            chmod +x "$HOME/bin/fzf-pick-project"

            patchShebangs "$HOME/bin" "$commands"
            export PATH="$HOME/bin:$PATH"

            fail() { echo "FAIL: $*" >&2; exit 1; }
            ok() { echo "ok - $*"; }

            tmux -f ${tmuxConf} new-session -d -s wiring -c "$HOME" ||
              fail "generated tmux.conf did not load"

            keys=$(tmux list-keys -T root)
            grep -q 'M-x .*kill-session' <<< "$keys" || fail "M-x is not bound to kill-session"
            grep -q 'M-i .*tmux-pick-session' <<< "$keys" || fail "M-i is not bound to the picker"
            ok "config loads with the bindings"

            hooks=$(tmux show-hooks -g)
            grep -q 'client-attached\[55\].*restore_pins' <<< "$hooks" ||
              fail "restore_pins is not hooked to client-attached"
            grep -q 'client-session-changed\[55\].*restore_pins' <<< "$hooks" ||
              fail "restore_pins is not hooked to client-session-changed"
            grep -q 'window-unlinked\[55\].*save_pins' <<< "$hooks" ||
              fail "save_pins is not hooked to window-unlinked"
            ok "pins hooks registered"

            tmux new-session -d -s proj -n editor -c "$HOME" "tail -f /dev/null"
            tmux new-window -t proj: -n mon "tail -f /dev/null"
            sleep 1

            # Pin the second window's pane, dump it, then kill the first
            # window so indexes shift before restoring: the pin must follow
            # the pane, not land on whatever pane now holds the old index.
            pinned_pane=$(tmux display-message -p -t proj:mon '#{pane_id}')
            tmux set -p -t "$pinned_pane" @pinned 1
            tmux run-shell -t proj "$commands save_pins"
            sleep 1
            awk -F'\t' -v p="$pinned_pane" '$1=="proj" && $NF==p{f=1} END{exit !f}' \
              "$XDG_STATE_HOME/tmux/pinned" ||
              fail "save_pins wrote no pane_id-keyed dump"

            tmux kill-window -t proj:editor
            for pane_id in $(tmux list-panes -a -F '#{pane_id}'); do
              tmux set -p -t "$pane_id" @pinned 0 2>/dev/null || true
            done
            tmux run-shell -t proj "$commands restore_pins"
            sleep 1
            [ "$(tmux show-options -t "$pinned_pane" -pqv @pinned)" = "1" ] ||
              fail "restore_pins did not replay @pinned on the pinned pane"
            pinned_count=0
            for pane_id in $(tmux list-panes -a -F '#{pane_id}'); do
              [ "$(tmux show-options -t "$pane_id" -pqv @pinned)" = "1" ] &&
                pinned_count=$((pinned_count + 1))
            done
            [ "$pinned_count" = "1" ] ||
              fail "restore_pins pinned a pane other than the pinned one (count=$pinned_count)"
            ok "@pinned round-trips and follows the pane, not the index"

            user=$(whoami)
            tmux new-session -d -s "$user(kept)" -c "$HOME"
            sleep 1

            rows=$(tmux-pick-session --lines)
            [ -n "$rows" ] || fail "picker rendered no rows"
            grep -q "^$user(kept)"$'\t' <<< "$rows" || fail "session missing from picker"
            grep -q 'kept' <<< "$(cut -f2- <<< "$rows")" || fail "label missing"
            grep -qE '^\S*\t.*\(kept\)' <<< "$rows" &&
              fail "label still carries the $user(...) wrapper"
            grep -q '󰒲' <<< "$rows" && fail "live session rendered as sleeping"
            ok "picker lists live sessions and strips name wrappers"

            proj_session="$(whoami)($(basename "$repo"))"
            tmux run-shell -t wiring "tmux-pick-project" || true
            sleep 2
            tmux has-session -t "=$proj_session" 2>/dev/null ||
              fail "tmux-pick-project did not create $proj_session"
            [ "$(tmux list-panes -s -t "=$proj_session" -F '#{pane_current_path}' | head -1)" = "$repo" ] ||
              fail "cold start did not open in the project (got: $(tmux list-panes -s -t "=$proj_session" -F '#{pane_current_path}'), want: $repo)"
            ok "Alt+f cold start creates the session in the project"

            # A session rooted in a deleted worktree used to end up with idle
            # shells stranded in a dead directory; they get restarted at the
            # project root instead of inheriting the drift.
            dead="$repo/.worktrees/gone"
            mkdir -p "$dead"
            tmux kill-session -t "=$proj_session"
            tmux new-session -ds "$proj_session" -c "$dead"
            sleep 1
            rm -rf "$dead"

            tmux run-shell -t wiring "tmux-pick-project" || true
            sleep 2
            tmux has-session -t "=$proj_session" 2>/dev/null ||
              fail "picker dropped the session instead of switching to it"
            [ "$(tmux list-panes -s -t "=$proj_session" -F '#{pane_current_path}')" = "$repo" ] ||
              fail "idle shell in a deleted directory was not restarted at the project root"
            ok "shell stranded in a deleted worktree is restarted in the project"

            # Alt+f runs the picker in a pane of an ATTACHED client. Commands
            # that refuse to nest there (attach-session: "sessions should be
            # nested with care") close the window instead of switching, and no
            # detached-only assertion above notices.
            script -qfc "tmux attach-session -t =wiring" /dev/null >/dev/null 2>&1 &
            client_pid=$!
            client_session() { tmux list-clients -F '#{client_session}' 2>/dev/null; }
            for _ in $(seq 20); do
              [ -n "$(client_session)" ] && break
              sleep 0.5
            done
            [ -n "$(client_session)" ] || fail "no client attached — cannot test the nested path"

            tmux kill-session -t "=$proj_session"
            tmux send-keys -t wiring:1 "tmux-pick-project" Enter
            for _ in $(seq 20); do
              client_session | grep -qx "$proj_session" && break
              sleep 0.5
            done
            client_session | grep -qx "$proj_session" ||
              fail "picker did not switch the attached client to $proj_session"
            ok "picker switches the client it was invoked from"
            kill "$client_pid" 2>/dev/null || true
            sleep 1

            # Alt+h runs the agent picker in a popup; a selection dispatches
            # the same toggle the popup bind would. The picker itself needs
            # fzf, so the stub stands in for one made selection.
            cat > "$HOME/bin/codex" <<EOF
            #!/bin/sh
            exec tail -f /dev/null
            EOF
            cat > "$HOME/bin/tmux-codex" <<EOF
            #!/bin/sh
            exec codex "\$@"
            EOF
            cat > "$HOME/bin/tmux-pick-agent" <<EOF
            #!/bin/sh
            exec "$commands" toggle_agent_window codex tmux-codex
            EOF
            chmod +x "$HOME/bin/codex" "$HOME/bin/tmux-codex" "$HOME/bin/tmux-pick-agent"

            tmux run-shell -t wiring "tmux-pick-agent"
            sleep 1
            tmux list-windows -t wiring -F '#{window_name}' | grep -qx codex ||
              fail "agent picker dispatch did not open the codex window"

            tmux run-shell -t wiring "tmux-pick-agent"
            sleep 1
            [ "$(tmux list-windows -t wiring -F '#{window_name}' | grep -cx codex)" = "1" ] ||
              fail "second agent dispatch opened a duplicate window"
            ok "agent picker opens one window per agent and reuses it"

            tmux new-session -d -s move -c "$HOME"
            tmux split-window -h -t move
            sleep 1

            right=$(tmux display-message -p -t move '#{pane_id}')
            left=$(tmux list-panes -t move -F '#{pane_id}' | grep -vxF "$right")

            tmux run-shell -t move "$commands move_pane L"
            sleep 1
            [ "$(tmux list-panes -t move -F '#{pane_id}' | head -1)" = "$right" ] ||
              fail "move_pane L did not swap the pane leftwards"
            ok "move_pane L swaps with the left neighbour"

            tmux run-shell -t move "$commands move_pane R"
            sleep 1
            [ "$(tmux list-panes -t move -F '#{pane_id}' | head -1)" = "$left" ] ||
              fail "move_pane R did not swap the pane back"
            ok "move_pane R swaps with the right neighbour"

            tmux new-window -t move -c "$HOME"
            tmux split-window -v -t move
            sleep 1
            stacked=$(tmux list-panes -F '#{pane_id}' | tr '\n' ' ')
            top=$(tmux list-panes -F '#{pane_id}' | head -1)
            bottom=$(tmux list-panes -F '#{pane_id}' | tail -1)

            tmux select-pane -t "$top"
            tmux run-shell "$commands move_pane U"
            tmux select-pane -t "$bottom"
            tmux run-shell "$commands move_pane D"
            sleep 1
            [ "$(tmux list-panes -F '#{pane_id}' | tr '\n' ' ')" = "$stacked" ] ||
              fail "move_pane U/D moved a pane that already spans the window width"
            ok "move_pane U/D no-op at the edge they are pushing towards"

            touch "$out"
          '';
    };
}
