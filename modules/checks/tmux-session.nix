{ self, ... }:
{
  # `nix flake check` drives a real tmux server against the real generated
  # config and the real lazy-tmux binary, then asserts the session save/restore
  # contract end to end. Everything here is logic that fails silently: a
  # snapshot that comes back without window names, a restore that drops
  # @pinned, a picker that renders zero rows. The sandbox has ptys, so tmux
  # runs for real — no mocking of the thing under test.
  #
  # Deliberately not covered: fzf's interactive layer (the picker is exercised
  # through its `--lines` mode), `claude --resume` (needs a Claude Code
  # transcript directory to detect), and anything that needs an attached
  # client. The sandbox server has no client, so `#{pane_id}` does not resolve
  # for the display-message calls in toggle_pin/kill_pane, and the
  # client-attached hook never fires — hence save_pins/restore_pins are driven
  # directly here, with the hook wiring asserted separately in section 1.
  perSystem =
    { pkgs, ... }:
    let
      lazy-tmux = pkgs.callPackage (self + "/modules/packages/_lazy-tmux.nix") { };

      # The config home-manager actually deploys, not a stand-in: this is what
      # carries the daemon launch, the M-o picker binding and the hook wiring.
      tmuxConf = self.homeConfigurations.stubbe.config.xdg.configFile."tmux/tmux.conf".source;
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

            # The sandbox has /bin/sh but no /usr/bin/env, so the scripts'
            # `#!/usr/bin/env bash|zsh` shebangs cannot exec. Copy them out and
            # let patchShebangs rewrite the interpreters to store paths — this
            # keeps them running as scripts (PATH lookup, shebang and all)
            # instead of being fed to an explicit interpreter the real system
            # never uses.
            commands="$HOME/.config/tmux/scripts/commands.sh"
            install -m755 ${self}/src/tmux/scripts/commands.sh "$commands"
            mkdir -p "$HOME/bin"
            install -m755 \
              ${self}/bin/tmux-pick-session \
              ${self}/bin/tmux-pick-project \
              ${self}/bin/tmux-new-session \
              "$HOME/bin/"

            # tmux-pick-project shells out to the interactive fzf picker; stub it
            # with a fixed answer so the rest of the Alt+f path is exercised.
            repo="$HOME/repo"
            mkdir -p "$repo"
            cat > "$HOME/bin/fzf-pick-project" <<EOF
            #!/bin/sh
            echo "$repo"
            EOF
            chmod +x "$HOME/bin/fzf-pick-project"

            patchShebangs "$HOME/bin" "$commands"
            export PATH="$HOME/bin:$PATH"

            # A long interval keeps the daemon the deployed config starts from
            # snapshotting mid-assertion; it still saves once at startup, which
            # is why every check below saves explicitly instead of relying on it.
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

            # ---------------------------------------------------------------
            # 1. the deployed config loads, and the lazy-tmux wiring is in it
            # ---------------------------------------------------------------
            tmux -f ${tmuxConf} new-session -d -s wiring -c "$HOME" ||
              fail "generated tmux.conf did not load"

            keys=$(tmux list-keys -T root)
            grep -q 'M-x .*sleep_session' <<< "$keys" || fail "M-x is not bound to sleep_session"
            grep -q 'M-o .*lazy-tmux picker' <<< "$keys" || fail "M-o is not bound to the picker"
            ok "config loads with the lazy-tmux bindings"

            hooks=$(tmux show-hooks -g)
            grep -q 'client-attached\[55\].*restore_pins' <<< "$hooks" ||
              fail "restore_pins is not hooked to client-attached"
            grep -q 'client-session-changed\[55\].*restore_pins' <<< "$hooks" ||
              fail "restore_pins is not hooked to client-session-changed"
            grep -q 'client-detached\[60\].*save_state' <<< "$hooks" ||
              fail "save_state is not hooked to client-detached"
            ok "pins and save hooks registered"

            # ---------------------------------------------------------------
            # 2. window names, pane commands and scrollback survive a restore
            # ---------------------------------------------------------------
            # The marker is echoed by the pane's own command rather than
            # send-keys: key-name lookup varies with the loaded config, and the
            # point here is the snapshot, not tmux's key parser. `exec sh` keeps
            # the pane a shell, which is what makes lazy-tmux capture its
            # scrollback. `tail` in the second window is the non-shell command
            # whose replay we assert (no terminfo needed, unlike top).
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

            # Restoring by name has to switch automatic-rename off, or tmux
            # renames the window to whatever runs in it on the next redraw.
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

            # ---------------------------------------------------------------
            # 3. @pinned is a pane option: restore drops it, restore_pins re-adds
            # ---------------------------------------------------------------
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

            # ---------------------------------------------------------------
            # 4. sleep_session saves and closes, leaving a fresher snapshot
            # ---------------------------------------------------------------
            before=$(jq -r .captured_at "$LAZY_TMUX_DATA_DIR/sessions/proj.json")
            sleep 1
            tmux run-shell -t proj "$commands sleep_session"
            sleep 3

            tmux has-session -t =proj 2>/dev/null && fail "sleep_session left the session running"
            after=$(jq -r .captured_at "$LAZY_TMUX_DATA_DIR/sessions/proj.json")
            [ "$after" != "$before" ] || fail "sleep_session did not re-save before killing"
            ok "sleep_session saves then closes"

            # ---------------------------------------------------------------
            # 5. picker rows: live vs sleeping, dead directories hidden,
            #    "$(whoami)(repo)" labels stripped
            # ---------------------------------------------------------------
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

            # A live session renders without the glyph.
            lazy-tmux wakeup --session "$user(kept)" >/dev/null
            sleep 2
            live_row=$(tmux-pick-session --lines | grep "^$user(kept)")
            grep -q '󰒲' <<< "$live_row" && fail "live session rendered as sleeping"
            ok "live session rendered as live"

            # ---------------------------------------------------------------
            # 6. Alt+f: cold start creates the session, second run wakes the
            #    snapshot instead of starting over
            # ---------------------------------------------------------------
            proj_session="$(whoami)($(basename "$repo"))"
            # Runs inside the server so $TMUX is set; the trailing
            # switch-client has no client to move here, so ignore the status
            # and assert on the session state instead.
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

            touch "$out"
          '';
    };
}
