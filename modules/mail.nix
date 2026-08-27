# Mail: aerc as the client, mbsync mirroring IMAP into a local maildir, and
# notmuch indexing it. One file, so the maildir path is a single let-binding
# instead of a value restated in four places with a "must match" comment.
{ inputs, ... }:
{
  flake.modules.homeManager.mail =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      home = config.home.homeDirectory;
      maildir = "${home}/.local/share/mail";

      # sops-decrypted IMAP/SMTP passwords. mbsync's PassCmd and aerc's
      # outgoing-cred-cmd both `cat` these, so there is one copy of each
      # credential on disk and one declaration of it here.
      passwords = {
        kontainer = "${home}/.config/aerc/passwords/kontainer";
        gmail = "${home}/.config/aerc/passwords/gmail";
      };

      mbsyncrc = ''
        # ─── Kontainer (Exchange / IMAPS) ────────────────────────────
        IMAPAccount kontainer
        Host ex.konformit.com
        Port 993
        User abs@kontainer.com
        PassCmd "cat ${passwords.kontainer}"
        TLSType IMAPS
        AuthMechs LOGIN
        # Exchange's IMAP layer pipelines FETCH responses in a way that trips
        # mbsync's parser ("malformed FETCH response: unexpected attribute").
        # Forcing one command at a time avoids the race.
        PipelineDepth 1

        IMAPStore kontainer-remote
        Account kontainer

        MaildirStore kontainer-local
        Path ${maildir}/kontainer/
        Inbox ${maildir}/kontainer/INBOX
        SubFolders Verbatim

        Channel kontainer
        Far :kontainer-remote:
        Near :kontainer-local:
        Patterns "INBOX" "Sent" "Drafts" "Archive"
        Create Both
        Expunge Both
        SyncState *
        # Cap the initial pull — the server has ~5k INBOX messages, most years
        # old. The recent ~2k is plenty for local search; older mail still
        # lives on the server and can be reached on demand.
        MaxMessages 2000
        ExpireUnread no

        # ─── Gmail ───────────────────────────────────────────────────
        # [Gmail]/All Mail mirrors every message ever, so sync only inbox /
        # sent / drafts. Archive (= [Gmail]/All Mail in aerc) still works
        # because aerc moves the maildir file into
        # ${maildir}/gmail/[Gmail]/All Mail/ on archive, and mbsync pushes
        # that copy up on the next sync.
        IMAPAccount gmail
        Host imap.gmail.com
        Port 993
        User alexander.bugge.stage@gmail.com
        PassCmd "cat ${passwords.gmail}"
        TLSType IMAPS
        AuthMechs LOGIN

        IMAPStore gmail-remote
        Account gmail

        MaildirStore gmail-local
        Path ${maildir}/gmail/
        Inbox ${maildir}/gmail/INBOX
        SubFolders Verbatim

        Channel gmail
        Far :gmail-remote:
        Near :gmail-local:
        Patterns "INBOX" "[Gmail]/Sent Mail" "[Gmail]/Drafts" "[Gmail]/All Mail"
        Create Both
        Expunge Both
        SyncState *
        # Same reasoning as above, so a long-lived account does not drag in
        # years of history on first sync.
        MaxMessages 5000
        ExpireUnread no
      '';

      # `new.tags = unread` is the contract between notmuch and aerc: aerc
      # strips the tag when the user opens a message, notmuch's
      # maildir.synchronize_flags (bidirectional flag↔tag sync) then renames
      # the maildir file to add the `S` flag, and mbsync propagates that back
      # to IMAP on the next run. Nothing else marks mail as read.
      notmuchConfig = (pkgs.formats.ini { }).generate "notmuch-config" {
        database.path = maildir;
        user = {
          name = "Alexander Bugge Stage";
          primary_email = "abs@kontainer.com";
          other_email = "alexander.bugge.stage@gmail.com";
        };
        new = {
          tags = "unread;inbox;";
          ignore = "";
        };
        search.exclude_tags = "deleted;spam;";
        maildir.synchronize_flags = true;
      };

      # Tagging used to live in a notmuch post-new hook, but the hook dir is
      # inside ${maildir}/.notmuch/ which notmuch creates itself —
      # home-manager refuses to symlink into a directory it does not own, so
      # the hook never landed. Inlining here applies the tags on every sync
      # regardless of how activation went.
      #
      # path: (recursive) and folder: (exact) rather than regex — regex
      # delimiters cannot contain spaces, which breaks on `[Gmail]/All Mail`.
      mailSync = pkgs.stubbe.bashApp {
        name = "mail-sync";
        runtimeInputs = with pkgs; [
          isync
          notmuch
          util-linux # flock
        ];
        text = ''
          # Sync every channel by default; pass channel name(s) to limit.
          # Run channels independently so one account's outage (auth, network,
          # server-side flake-out) does not black-hole the other.
          if [ "$#" -eq 0 ]; then
            channels=(kontainer gmail)
          else
            channels=("$@")
          fi

          # mail-sync is invoked from three independent schedulers: the systemd
          # timer, aerc's per-account check-mail-cmd, and the user from a
          # shell. Without serialization they collide on mbsync's per-channel
          # SyncState lock, leaving half-synced folders in "cannot be opened
          # anymore" state. Per-channel flock with -E 75 distinguishes "lock
          # busy" (skip cleanly) from "mbsync genuinely failed" (report).
          lock_dir="''${XDG_RUNTIME_DIR:-/tmp}"
          mkdir -p "$lock_dir"

          failed=()
          for ch in "''${channels[@]}"; do
            rc=0
            flock -n -E 75 "$lock_dir/mail-sync-$ch.lock" mbsync "$ch" || rc=$?
            case "$rc" in
              0) ;;
              75) echo "mail-sync: $ch already syncing elsewhere, skipping" >&2 ;;
              *)
                echo "mail-sync: mbsync $ch failed (exit $rc)" >&2
                failed+=("$ch")
                ;;
            esac
          done

          # Always reindex — a partial sync is still worth indexing so aerc
          # reflects whatever did land. --quiet is a `new` subcommand flag, and
          # suppresses per-message progress; the "Ignoring non-mail file" lines
          # come from mbsync, not notmuch.
          notmuch new --quiet || true

          notmuch tag +kontainer -- 'path:kontainer/** and not tag:kontainer' || true
          notmuch tag +gmail     -- 'path:gmail/**     and not tag:gmail'     || true
          notmuch tag -inbox -- 'tag:inbox and not folder:kontainer/INBOX and not folder:gmail/INBOX' || true

          if [ ''${#failed[@]} -gt 0 ]; then
            echo "mail-sync: failed channels: ''${failed[*]}" >&2
            exit 1
          fi
        '';
      };

      # maildir-account-path scopes each tab's dirlist (and the folder names
      # used by copy-to/postpone/archive) to that account's subtree. Without
      # it, aerc enumerates the shared maildir root and every tab shows both
      # accounts' folders.
      #
      # aerc ≥0.22 deprecated maildir-store and explicit database paths in the
      # source URL — both now come from the notmuch config, which aerc finds
      # via NOTMUCH_CONFIG (set below).
      accountsConf = (pkgs.formats.ini { }).generate "aerc-accounts.conf" {
        kontainer = {
          source = "notmuch://";
          maildir-account-path = "kontainer";
          query-map = "${home}/.config/aerc/queries-kontainer";
          exclude-tags = "deleted,spam";
          default = "INBOX";
          folders = "INBOX,Sent";
          from = "Alexander Bugge Stage <abs@kontainer.com>";
          outgoing = "smtp+login://abs@kontainer.com@ex.konformit.com:587";
          outgoing-cred-cmd = "cat ${passwords.kontainer}";
          copy-to = "Sent";
          postpone = "Drafts";
          archive = "Archive";
          check-mail-cmd = "${lib.getExe mailSync} kontainer";
          check-mail = "30s";
        };
        gmail = {
          source = "notmuch://";
          maildir-account-path = "gmail";
          query-map = "${home}/.config/aerc/queries-gmail";
          exclude-tags = "deleted,spam,trash";
          default = "INBOX";
          folders = "INBOX,Sent";
          from = "Alexander Bugge Stage <alexander.bugge.stage@gmail.com>";
          outgoing = "smtp+plain://alexander.bugge.stage@gmail.com@smtp.gmail.com:587";
          outgoing-cred-cmd = "cat ${passwords.gmail}";
          copy-to = "[Gmail]/Sent Mail";
          postpone = "[Gmail]/Drafts";
          archive = "[Gmail]/All Mail";
          check-mail-cmd = "${lib.getExe mailSync} gmail";
          check-mail = "30s";
        };
      };

      # Virtual folder name → notmuch query; aerc opens the named folder by
      # running its query against the local index. Sent is virtualised so the
      # gmail sidebar reads "Sent" instead of "[Gmail]/Sent Mail".
      queries = {
        kontainer = ''
          INBOX = tag:kontainer and tag:inbox
          Sent  = folder:/^kontainer\/Sent$/
        '';
        gmail = ''
          INBOX = tag:gmail and tag:inbox
          Sent  = folder:"gmail/[Gmail]/Sent Mail"
        '';
      };

      # Focus an existing aerc window if one is open, otherwise spawn a new
      # alacritty for it. The window is launched with --class so we can
      # match by app-id/class, which (unlike the title) stays stable as
      # aerc updates the displayed folder/count.
      mailOpen = pkgs.stubbe.bashApp {
        name = "mail-open";
        # pkill/jq must not depend on the host providing them.
        runtimeInputs = with pkgs; [
          procps
          jq
        ];
        text = ''
          APP_ID="aerc-mail"

          spawn_term() {
            # aerc ignores SIGHUP, so closing its window leaves the process orphaned and
            # window-less forever, still owning $XDG_RUNTIME_DIR/aerc.sock — every later
            # `aerc :<cmd>` IPC call (see binds.conf) then lands in that ghost instead of
            # the live instance. We only get here when no aerc window matched, so any
            # aerc still running is a ghost. SIGTERM shuts it down cleanly.
            pkill -TERM -f '/bin/aerc$' || true
            ${config.stubbe.paths.terminal} --class "$APP_ID" -e aerc
          }

          if [[ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]] && command -v hyprctl &> /dev/null; then
            addr=$(hyprctl -j clients | jq -r --arg c "$APP_ID" '.[] | select(.class == $c) | .address' | head -n1)
            if [[ -n "$addr" ]]; then
              ws=$(hyprctl -j activeworkspace | jq -r '.id')
              # Legacy `hyprctl dispatch <name> <args>` is rejected under the Lua config
              # (parsed as hl.dispatch(<args>) Lua), and there is no by-address
              # move-to-workspace dispatcher. Reproduce `movetoworkspace ws,address:addr`
              # by focusing the window (hy3 moves the *focused* window) then moving it to
              # the captured workspace with follow — same end state: aerc on the current
              # workspace, focused.
              hyprctl dispatch "hl.dsp.focus({ window = 'address:$addr' })"
              hyprctl dispatch "hl.plugin.hy3.move_to_workspace('$ws', { follow = true })"
            else
              spawn_term
            fi
          elif [[ "$XDG_CURRENT_DESKTOP" == "niri" ]] && command -v niri &> /dev/null; then
            id=$(niri msg --json windows | jq -r --arg c "$APP_ID" '.[] | select(.app_id == $c) | .id' | head -n1)
            if [[ -n "$id" ]]; then
              ws=$(niri msg --json workspaces | jq -r '.[] | select(.is_focused) | .idx')
              niri msg action move-window-to-workspace --window-id "$id" "$ws"
              niri msg action focus-window --id "$id"
            else
              spawn_term
            fi
          else
            spawn_term
          fi
        '';
      };

      # Extract and process List-Unsubscribe from email — bypasses DKIM
      # validation issues in aerc. Reads the message on stdin.
      mailUnsubscribe = pkgs.stubbe.bashApp {
        name = "mail-unsubscribe";
        text = ''
          # Absent headers make the greps below fail legitimately; the script
          # branches on empty results instead of aborting.
          set +e +o pipefail

          email=$(cat)

          # Extract List-Unsubscribe header
          unsub_header=$(echo "$email" | grep -i "^List-Unsubscribe:" | head -1)

          if [ -z "$unsub_header" ]; then
            echo "Error: No List-Unsubscribe header found"
            exit 1
          fi

          # Extract URL (handles both <URL> and plain URL formats)
          url=$(echo "$unsub_header" | grep -oP 'https?://[^>,\s]+' | head -1)

          if [ -z "$url" ]; then
            # Try extracting mailto link
            mailto=$(echo "$unsub_header" | grep -oP 'mailto:[^>,\s]+' | head -1)
            if [ -n "$mailto" ]; then
              echo "Found mailto unsubscribe: $mailto"
              echo "Opening in aerc compose..."
              aerc "$mailto"
              exit 0
            fi
            echo "Error: No valid unsubscribe URL or mailto found"
            exit 1
          fi

          # Check for List-Unsubscribe-Post header (RFC 8058 - one-click unsubscribe)
          unsub_post=$(echo "$email" | grep -i "^List-Unsubscribe-Post:" | head -1)

          if [ -n "$unsub_post" ]; then
            # RFC 8058: POST with List-Unsubscribe=One-Click
            echo "Processing one-click unsubscribe..."
            response=$(curl -sS -X POST -d "List-Unsubscribe=One-Click" "$url" -w "\n%{http_code}" -o /dev/null)
            http_code=$(echo "$response" | tail -n1)

            if [ "$http_code" = "200" ] || [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
              echo "✓ Successfully unsubscribed"
              exit 0
            else
              echo "Warning: Unsubscribe request returned HTTP $http_code"
              echo "URL: $url"
              exit 1
            fi
          else
            # Standard GET-based unsubscribe
            echo "Processing unsubscribe request..."
            response=$(curl -sS -L "$url" -w "\n%{http_code}" -o /dev/null)
            http_code=$(echo "$response" | tail -n1)

            if [ "$http_code" = "200" ] || [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
              echo "✓ Successfully unsubscribed"
              exit 0
            else
              echo "Warning: Unsubscribe request returned HTTP $http_code"
              echo "URL: $url"
              exit 1
            fi
          fi
        '';
      };

      # Sourced by mail-pager for text/html parts. conceallevel=2 hides link
      # destinations so the body reads as prose; the destination is shown in a
      # float instead (overlay layer, so nothing in the rendered message moves).
      # Injections must be followed explicitly: without ignore_injections=false
      # the node chain stops at `inline` (markdown), never reaching the
      # markdown_inline nodes that actually carry the URL.
      mailPagerLua = pkgs.writeText "mail-pager.lua" ''
        local function url_at_cursor()
          local ok, node = pcall(vim.treesitter.get_node, { ignore_injections = false })
          if not ok or not node then
            return nil
          end
          while node do
            local kind = node:type()
            if kind == "uri_autolink" then
              -- <https://example.com> -- strip the angle brackets the syntax requires.
              return vim.treesitter.get_node_text(node, 0):match("^<(.*)>$")
            elseif kind == "inline_link" or kind == "image" then
              for child in node:iter_children() do
                if child:type() == "link_destination" then
                  return vim.treesitter.get_node_text(child, 0)
                end
              end
            end
            node = node:parent()
          end
          return nil
        end

        -- open_floating_preview closes itself on the next CursorMoved and reuses its
        -- own window, so moving between two links swaps the contents rather than
        -- stacking floats.
        vim.api.nvim_create_autocmd("CursorMoved", {
          buffer = 0,
          callback = function()
            local url = url_at_cursor()
            if url then
              vim.lsp.util.open_floating_preview({ url }, "", {
                focusable = false,
                border = "rounded",
              })
            end
          end,
        })
      '';

      # Aerc viewer pager: read the (already-filtered) message body in nvim.
      # Minimal nvim, same shape as the [compose] editor: no plugins, no swap, no
      # shada — the buffer is throwaway. Everything that would pollute a mouse
      # drag-select is off (gutter, statusline, ruler); `mouse=` leaves selection to
      # the terminal, and clipboard=unnamedplus makes a plain `y` land in wl-copy.
      # nvim always paints from the top, so no bottom-parked first screen.
      # Closing the viewer is aerc's job: q is bound in [view].
      mailPager = pkgs.stubbe.bashApp {
        name = "mail-pager";
        text = ''
          # aerc exports AERC_MIME_TYPE to the pager, not only to the filters the
          # manual documents (verified against 0.22). The part type decides how to
          # read it.
          case "''${AERC_MIME_TYPE:-}" in
          image/*)
            # chafa emits ANSI art, which nvim would show as literal escape codes.
            exec less -Rc
            ;;
          text/html)
            # Already through html-to-md, so it really is markdown. Colours come from
            # treesitter rather than `syntax on`: the markdown and markdown_inline
            # parsers ship inside the neovim derivation, so this holds under -u NONE
            # with no plugins, and the default colourscheme defines the @markup.* groups.
            # conceallevel hides the markup itself; mailPagerLua puts the hidden link
            # destination in a float so revealing one never reflows the line. Sourced
            # with `silent!` so a missing Lua half costs you the float and nothing else
            # — bare `-S` raises a modal E484 that blocks reading the message at all.
            syntax=(
              -c 'set filetype=markdown conceallevel=2 concealcursor=nvic'
              -c 'lua pcall(vim.treesitter.start, 0, "markdown")'
              -c 'silent! source ${mailPagerLua}'
            )
            ;;
          *)
            # Prose the sender typed by hand. Markdown conceal here would swallow
            # literal **, ` and (…) that were never markup. ft=mail is nvim's own
            # syntax for this: quote depth, headers, signatures.
            syntax=(
              -c 'syntax enable'
              -c 'set filetype=mail'
            )
            ;;
          esac

          # Normal is cleared last so aerc's styleset background shows through instead
          # of nvim's — `syntax enable` would otherwise reset it.
          exec nvim -u NONE -U NONE --noplugin -n -i NONE -M \
            -c 'set mouse= clipboard=unnamedplus' \
            -c 'set nonumber norelativenumber signcolumn=no nolist laststatus=0 noruler noshowcmd' \
            -c 'set linebreak termguicolors' \
            "''${syntax[@]}" \
            -c 'hi Normal guibg=NONE ctermbg=NONE' \
            -
        '';
      };
    in
    lib.mkIf config.features.desktop {
      sops.secrets = {
        aerc-kontainer = pkgs.stubbe.secret {
          name = "aerc-kontainer";
          path = passwords.kontainer;
        };
        aerc-gmail = pkgs.stubbe.secret {
          name = "aerc-gmail";
          path = passwords.gmail;
        };
      };

      home = {
        packages = [
          mailSync
          # aerc's text/html filter: parses with html5ever (kuchikiki),
          # flattens layout tables (a heuristic preserves real data tables),
          # strips MSO/Word noise, then renders Markdown via htmd. Single
          # static binary — github:stubbedev/html-to-md.
          inputs.html-to-md.packages.${pkgs.stdenv.hostPlatform.system}.default
          mailOpen
          mailUnsubscribe
          mailPager
        ]
        ++ (with pkgs; [
          # The client itself, and the address-book/calendar tooling beside it.
          aerc
          # aerc's image/* filter (aerc.conf) renders through chafa.
          chafa
          # IMAP → local maildir mirror, paired with notmuch indexing. aerc's
          # `source=notmuch://` reads the indexed maildir rather than talking
          # to IMAP per message; mbsync propagates flag/tag changes back.
          isync
          notmuch
        ]);

        # aerc takes the database path from notmuch config discovery, so point
        # that at the legacy ~/.notmuch-config we write rather than leaving
        # aerc to guess XDG paths that do not exist here.
        sessionVariables.NOTMUCH_CONFIG = "${home}/.notmuch-config";

        file = {
          # mbsync still reads ~/.mbsyncrc by default in nixpkgs' isync.
          ".mbsyncrc".text = mbsyncrc;
          # notmuch reads ~/.notmuch-config (the legacy path) regardless of
          # XDG when the file exists — keep it explicit.
          ".notmuch-config".source = notmuchConfig;
        };
      };

      xdg.configFile = {
        "aerc/aerc.conf".text = ''
          [general]
          default-save-path=~/Downloads
          # accounts.conf contains no passwords (cred-cmds reference sops-decrypted
          # files at mode 0400). Skip aerc's 0600 check since the file is symlinked
          # from /nix/store and is therefore world-readable by design.
          unsafe-accounts-conf=true
          # Default 10s is too short for kontainer's Exchange server: its broken IMAP
          # pipelining forces mbsync to PipelineDepth=1 (one command at a time), and
          # even an incremental sync of a few hundred messages overruns 10s. The next
          # tick fires only after the current one completes, so a longer ceiling
          # doesn't pile up overlapping runs.
          check-mail-timeout=2m

          [compose]
          editor=nvim -u NONE -U NONE --noplugin \
            -c 'set notermguicolors' \
            -c 'set t_Co=0' \
            -c 'syntax off' \
            -c 'hi Normal ctermbg=NONE guibg=NONE'
          header-layout=To,Subject
          edit-headers=false

          [viewer]
          pager=mail-pager
          alternatives=text/html,text/plain

          [filters]
          text/html=html-to-md
          text/plain=cat
          text/calendar=calendar
          image/*=chafa --format symbols

          [ui]
          border-char-vertical="│"
          border-char-horizontal="─"
          styleset-name=catppuccin-macchiato
          # Default true. Stays explicit because the whole local-cache pipeline
          # (mbsync + notmuch synchronize_flags) hinges on the `unread` flag being
          # stripped exactly once, when the user opens the message viewer — not
          # while browsing the message list, syncing IMAP, or indexing the maildir.
          auto-mark-read=true
        '';
        "aerc/binds.conf".text = ''
          # LazyVim-inspired keybinds for aerc
          # Leader key is <Space>

          [messages]
          j = :next<Enter> # Next message
          k = :prev<Enter> # Previous message
          h = :prev-tab<Enter> # Previous tab
          l = :next-tab<Enter> # Next tab
          gg = :select 0<Enter> # Jump to first message
          G = :select -1<Enter> # Jump to last message
          <C-u> = :prev 10<Enter> # Scroll up 10
          <C-d> = :next 10<Enter> # Scroll down 10
          <PgUp> = :prev 100%<Enter> # Page up
          <PgDn> = :next 100%<Enter> # Page down
          <C-h> = :prev-tab<Enter> # Previous tab
          <C-l> = :next-tab<Enter> # Next tab
          <C-j> = :next-folder<Enter> # Next folder
          <C-k> = :prev-folder<Enter> # Previous folder
          <Up> = :prev<Enter> # Previous message
          <Down> = :next<Enter> # Next message
          <Left> = :prev-tab<Enter> # Previous tab
          <Right> = :next-tab<Enter> # Next tab
          <Space>r = :reply<Enter> # Reply
          <Space>R = :reply -a<Enter> # Reply all
          <Space>c = :compose<Enter>:prev-field<Enter> # Compose new, focus To
          <Space>F = :forward<Enter> # Forward
          q = :quit<Enter> # Quit
          <Space>m = :mark -t<Enter> # Mark as todo
          <Space>d = :delete<Enter> # Delete
          <Space>a = :archive<Enter> # Archive
          <Space><Tab> = :next-tab<Enter> # Next tab
          <Space><S-Tab> = :prev-tab<Enter> # Previous tab
          <Space>j = :next-folder<Enter> # Next folder
          <Space>k = :prev-folder<Enter> # Previous folder
          # Telescope/FZF-style search and filter
          <Space>ff = :filter<space> # Filter (live search)
          <Space>fs = :search<space>  # Search (persistent)
          <Space>fc = :clear<Enter> # Clear filter/search
          / = :filter<space> # Quick filter (like fzf)
          ? = :search<space>  # Quick search
          <Space>fh = :help keys<Enter> # Show key help
          <Space>? = :help keys<Enter> # Show key help
          <Space>fk = :help keys<Enter> # Show key help
          <Space>sd = :sort date<Enter> # Sort by date
          <Space>sD = :sort -r date<Enter> # Sort by date reverse
          <Space>sf = :sort from<Enter> # Sort by from
          <Space>sF = :sort -r from<Enter> # Sort by from reverse
          <Space>ss = :sort subject<Enter> # Sort by subject
          <Space>sS = :sort -r subject<Enter> # Sort by subject reverse
          <Space>tf = :flag -t<Enter> # Toggle important flag
          <Space>tr = :read -t<Enter> # Toggle read
          <Space>tu = :read -t<Enter> # Toggle read/unread (same as tr)
          <Space>mr = :read<Enter> # Mark as read
          <Space>mu = :unread<Enter> # Mark as unread
          <Space>mR = :pipe -m aerc :read<Enter> # Mark all marked as read
          <Space>mU = :pipe -m aerc :unread<Enter> # Mark all marked as unread
          <Enter> = :view<Enter> # View message
          # Bulk selection and operations
          v = :mark -t<Enter>:next<Enter> # Toggle mark and move to next
          V = :mark -v<Enter> # Visual mode - toggle all
          <Space>v = :mark -a<Enter> # Mark all
          <Space>V = :unmark -a<Enter> # Unmark all
          <Space>x = :pipe -m -b /bin/sh -c 'aerc :delete'<Enter> # Delete marked
          <Space>X = :pipe -m -b /bin/sh -c 'aerc :read'<Enter> # Mark marked as read
          d = :delete<Enter> # Quick delete current
          D = :pipe -m aerc :delete<Enter> # Delete marked emails

          [view]
          # aerc grabs these before the nvim pager sees them; :close tears the pager
          # terminal down with the viewer. IPC (`aerc :close` from a script) cannot do
          # this: IPC only resolves global-context commands, never view-context ones.
          # <Esc> is deliberately NOT bound: aerc decides before nvim ever sees a key, so
          # a bind here would steal <Esc> in every nvim mode, not just normal. Closing on
          # <Esc> is not worth losing visual/insert-mode exit inside the pager — `q`
          # closes. aerc also will not close the viewer when the pager exits on its own
          # (verified: `pager=cat` leaves the dead pane up), so nvim cannot do it either.
          q = :close<Enter> # Close
          J = :next<Enter> # Next message
          K = :prev<Enter> # Previous message
          <C-j> = :next-part<Enter> # Next part
          <C-k> = :prev-part<Enter> # Previous part
          <C-h> = :prev-tab<Enter> # Previous tab
          <C-l> = :next-tab<Enter> # Next tab
          <Space>r = :reply<Enter> # Reply
          <Space>R = :reply -a<Enter> # Reply all
          <Space>F = :forward<Enter> # Forward
          <Space>c = :close<Enter> # Close
          <Space>y = :accept<Enter> # Accept
          <Space>n = :decline<Enter> # Decline
          <Space>u = :pipe -m mail-unsubscribe<Enter>
          # parse-http-links (default on) collects the message's URLs; both commands
          # tab-complete over that list, which beats hunting for the link in the body.
          <Space>l = :open-link<space> # Open link
          <Space>L = :copy-link<space> # Copy link
          <Space>? = :help keys<Enter> # Show key help

          [compose]
          # Navigate between header fields
          <Tab> = :next-field<Enter> # Next field
          <S-Tab> = :prev-field<Enter> # Previous field
          <C-j> = :next-field<Enter> # Next field
          <C-k> = :prev-field<Enter> # Previous field

          [compose::editor]
          # Navigation in compose editor (before neovim opens for body)
          $noinherit = true
          $ex = <C-x>
          <Tab> = :next-field<Enter> # Next field
          <S-Tab> = :prev-field<Enter> # Previous field
          <C-j> = :next-field<Enter> # Next field
          <C-k> = :prev-field<Enter> # Previous field

          [compose::review]
          # When reviewing before sending
          y = :send<Enter> # Send email
          n = :abort<Enter> # Abort sending
          e = :edit<Enter> # Edit again
          p = :postpone<Enter> # Save as draft
          q = :abort<Enter> # Quit compose
        '';
        "aerc/accounts.conf".source = accountsConf;
        "aerc/queries-kontainer".text = queries.kontainer;
        "aerc/queries-gmail".text = queries.gmail;
      };

      stubbe.mutable = {
        # aerc rewrites nothing here, but stylesets are the thing you iterate
        # on by eye — link the checkout so an edit shows on the next launch.
        ".config/aerc/stylesets".src = "mail/stylesets";
      };

      # aerc reads via notmuch://, which fails with "No database found" when
      # the maildir or its .notmuch index do not exist yet — and mbsync
      # refuses to open a MaildirStore whose Path is missing ("Maildir error:
      # cannot open store"), since it does not mkdir its own Path. The timer
      # would hit that on every tick, so bootstrap the tree and an empty index
      # here: aerc then opens immediately and mbsync's first run has somewhere
      # to land.
      stubbe.setup.mail.script = ''
        mkdir -p ${lib.escapeShellArg "${maildir}/kontainer"} ${lib.escapeShellArg "${maildir}/gmail"}
        if [ ! -d ${lib.escapeShellArg "${maildir}/.notmuch"} ]; then
          ${lib.getExe pkgs.notmuch} --config="${home}/.notmuch-config" new --quiet || true
        fi
      '';

      # Sync every 30s so notifications fire promptly. mbsync STATUS-only
      # round-trips are cheap (~1-2s) when nothing changed, and mail-sync's own
      # flock stops concurrent runs piling up.
      systemd.user = {
        services.mail-sync = {
          Unit = {
            Description = "Sync IMAP -> local maildir + reindex with notmuch";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe mailSync;
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };
        timers.mail-sync = {
          Unit.Description = "Periodic mail sync";
          Timer = {
            OnBootSec = "30s";
            OnUnitActiveSec = "30s";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
