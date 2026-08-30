{ self, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      inherit (pkgs) lazy-tmux;

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
              pkgs.jq
              pkgs.git
              lazy-tmux
            ];
          }
          ''
            set -euo pipefail

            export HOME="$(mktemp -d)"
            export TMUX_TMPDIR="$(mktemp -d)"
            export XDG_RUNTIME_DIR="$(mktemp -d)"
            export XDG_STATE_HOME="$HOME/.local/state"
            export LAZY_TMUX_DATA_DIR="$HOME/snapshots"
            mkdir -p "$HOME/.config/tmux/scripts" "$LAZY_TMUX_DATA_DIR"

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

            cat > "$HOME/.config/lazy-tmux.toml" <<EOF
            data_dir = "$LAZY_TMUX_DATA_DIR"
            save_interval = "1h"
            [scrollback]
            enabled = true
            lines = 500
            EOF
            export LAZY_TMUX_CONFIG="$HOME/.config/lazy-tmux.toml"

            fail() { echo "FAIL: $*" >&2; exit 1; }
            ok() { echo "ok - $*"; }

            tmux -f ${tmuxConf} new-session -d -s wiring -c "$HOME" ||
              fail "generated tmux.conf did not load"

            keys=$(tmux list-keys -T root)
            grep -q 'M-x .*sleep_session' <<< "$keys" || fail "M-x is not bound to sleep_session"
            grep -q 'M-i .*lazy-tmux picker' <<< "$keys" || fail "M-i is not bound to the picker"
            ok "config loads with the lazy-tmux bindings"

            hooks=$(tmux show-hooks -g)
            grep -q 'client-attached\[55\].*restore_pins' <<< "$hooks" ||
              fail "restore_pins is not hooked to client-attached"
            grep -q 'client-session-changed\[55\].*restore_pins' <<< "$hooks" ||
              fail "restore_pins is not hooked to client-session-changed"
            grep -q 'client-detached\[60\].*save_state' <<< "$hooks" ||
              fail "save_state is not hooked to client-detached"
            ok "pins and save hooks registered"

            tmux new-session -d -s proj -n editor -c "$HOME" \
              "sh -c 'echo SCROLLBACK_MARKER; exec sh'"
            tmux new-window -t proj: -n mon "tail -f /dev/null"
            sleep 2

            lazy-tmux save --session proj >/dev/null
            tmux kill-session -t =proj
            sleep 1
            lazy-tmux wakeup --session proj >/dev/null || fail "wakeup failed"
            sleep 2

            names=$(tmux list-windows -t proj -F '#{window_index}:#{window_name}' | sort | tr '\n' ' ')
            [ "$names" = "1:editor 2:mon " ] || fail "window names not restored (got: $names)"
            ok "window names restored"

            for w in 1 2; do
              [ "$(tmux show-options -t proj:$w -wqv automatic-rename)" = "off" ] ||
                fail "automatic-rename still on for window $w — names would drift"
            done
            ok "automatic-rename disabled on restored windows"

            [ "$(tmux display-message -p -t proj:mon '#{pane_current_command}')" = "tail" ] ||
              fail "pane command not replayed"
            ok "pane command replayed"

            tmux capture-pane -p -S - -t proj:editor | grep -q SCROLLBACK_MARKER ||
              fail "scrollback not replayed"
            ok "scrollback replayed"

            tmux set -p -t proj:editor.1 @pinned 1
            tmux run-shell -t proj "$commands save_pins"
            sleep 1
            grep -q '^proj' "$XDG_STATE_HOME/tmux/pinned" || fail "save_pins wrote no dump"

            lazy-tmux save --session proj >/dev/null
            tmux kill-session -t =proj
            sleep 1
            lazy-tmux wakeup --session proj >/dev/null
            sleep 2

            [ -z "$(tmux show-options -t proj:1.1 -pqv @pinned)" ] ||
              fail "test assumes restore drops pane options, but @pinned survived"
            tmux run-shell -t proj "$commands restore_pins"
            sleep 1
            [ "$(tmux show-options -t proj:1.1 -pqv @pinned)" = "1" ] ||
              fail "restore_pins did not replay @pinned"
            ok "@pinned round-trips through save_pins/restore_pins"

            before=$(jq -r .captured_at "$LAZY_TMUX_DATA_DIR/sessions/proj.json")
            sleep 1
            tmux run-shell -t proj "$commands sleep_session"
            sleep 3

            tmux has-session -t =proj 2>/dev/null && fail "sleep_session left the session running"
            after=$(jq -r .captured_at "$LAZY_TMUX_DATA_DIR/sessions/proj.json")
            [ "$after" != "$before" ] || fail "sleep_session did not re-save before killing"
            ok "sleep_session saves then closes"

            user=$(whoami)
            gone="$HOME/worktree-gone"
            mkdir -p "$gone"
            tmux new-session -d -s "$user(gone)" -c "$gone"
            tmux new-session -d -s "$user(kept)" -c "$HOME"
            sleep 1
            lazy-tmux save --all >/dev/null
            tmux kill-session -t "=$user(gone)"
            tmux kill-session -t "=$user(kept)"
            rm -rf "$gone"
            sleep 1

            rows=$(tmux-pick-session --lines)
            [ -n "$rows" ] || fail "picker rendered no rows"
            grep -q "^$user(kept)"$'\t' <<< "$rows" || fail "sleeping session missing from picker"
            grep -q "^$user(gone)" <<< "$rows" &&
              fail "snapshot whose directory is gone is still offered"
            grep -q 'kept' <<< "$(cut -f2- <<< "$rows")" || fail "label missing"
            grep -qE '^\S*\t.*\(kept\)' <<< "$rows" &&
              fail "label still carries the $user(...) wrapper"
            grep -q '󰒲' <<< "$rows" || fail "sleeping row has no sleep glyph"
            ok "picker hides dead snapshots and strips name wrappers"

            lazy-tmux wakeup --session "$user(kept)" >/dev/null
            sleep 2
            live_row=$(tmux-pick-session --lines | grep "^$user(kept)")
            grep -q '󰒲' <<< "$live_row" && fail "live session rendered as sleeping"
            ok "live session rendered as live"

            proj_session="$(whoami)($(basename "$repo"))"
            tmux run-shell -t wiring "tmux-pick-project" || true
            sleep 2
            tmux has-session -t "=$proj_session" 2>/dev/null ||
              fail "tmux-pick-project did not create $proj_session"
            ok "Alt+f cold start creates the session"

            tmux new-window -t "=$proj_session" -n restored "tail -f /dev/null"
            sleep 1
            lazy-tmux save --session "$proj_session" >/dev/null
            tmux kill-session -t "=$proj_session"
            sleep 1

            tmux run-shell -t wiring "tmux-pick-project" || true
            sleep 3
            tmux list-windows -t "=$proj_session" -F '#{window_name}' | grep -qx restored ||
              fail "second Alt+f started a fresh session instead of waking the snapshot"
            ok "Alt+f wakes the snapshot on the second run"

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
