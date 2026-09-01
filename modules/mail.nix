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

      passwords = {
        kontainer = "${home}/.config/aerc/passwords/kontainer";
        gmail = "${home}/.config/aerc/passwords/gmail";
      };

      mbsyncrc = ''
        IMAPAccount kontainer
        Host ex.konformit.com
        Port 993
        User abs@kontainer.com
        PassCmd "cat ${passwords.kontainer}"
        TLSType IMAPS
        AuthMechs LOGIN
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
        MaxMessages 2000
        ExpireUnread no

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
        MaxMessages 5000
        ExpireUnread no
      '';

      # The contract with aerc: aerc strips this tag on open,
      # maildir.synchronize_flags renames the file to add `S`, and mbsync
      # propagates that to IMAP. Nothing else marks mail as read.
      notmuchConfig = pkgs.stubbe.gen.ini "notmuch-config" {
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

      # Not a notmuch post-new hook: that hook dir lives inside .notmuch/, which
      # notmuch creates itself and home-manager will not symlink into, so
      # Not regex: its delimiters cannot contain spaces, which breaks on
      # `[Gmail]/All Mail`.
      mailSync = pkgs.stubbe.bashApp {
        name = "mail-sync";
        runtimeInputs = with pkgs; [
          isync
          notmuch
          util-linux # flock
        ];
        text = ''
          if [ "$#" -eq 0 ]; then
            channels=(kontainer gmail)
          else
            channels=("$@")
          fi

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

      # Without maildir-account-path aerc enumerates the shared maildir root and
      # every tab shows both accounts' folders.
      accountsConf = pkgs.stubbe.gen.ini "aerc-accounts.conf" {
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

      mailOpen = pkgs.stubbe.bashApp {
        name = "mail-open";
        runtimeInputs = with pkgs; [
          procps
          jq
        ];
        text = ''
          APP_ID="aerc-mail"

          spawn_term() {
            pkill -TERM -f '/bin/aerc$' || true
            ${config.stubbe.paths.terminal} --class "$APP_ID" -e aerc
          }

          if [[ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]] && command -v hyprctl &> /dev/null; then
            addr=$(hyprctl -j clients | jq -r --arg c "$APP_ID" '.[] | select(.class == $c) | .address' | head -n1)
            if [[ -n "$addr" ]]; then
              ws=$(hyprctl -j activeworkspace | jq -r '.id')
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

      mailUnsubscribe = pkgs.stubbe.bashApp {
        name = "mail-unsubscribe";
        text = ''
          set +e +o pipefail

          email=$(cat)

          unsub_header=$(echo "$email" | grep -i "^List-Unsubscribe:" | head -1)

          if [ -z "$unsub_header" ]; then
            echo "Error: No List-Unsubscribe header found"
            exit 1
          fi

          url=$(echo "$unsub_header" | grep -oP 'https?://[^>,\s]+' | head -1)

          if [ -z "$url" ]; then
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

          unsub_post=$(echo "$email" | grep -i "^List-Unsubscribe-Post:" | head -1)

          if [ -n "$unsub_post" ]; then
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

      # Injections must be followed explicitly: without ignore_injections=false
      # the node chain stops at `inline` and never reaches the markdown_inline
      # nodes that carry the URL.
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

      mailPager = pkgs.stubbe.bashApp {
        name = "mail-pager";
        text = ''
          case "''${AERC_MIME_TYPE:-}" in
          image/*)
            exec less -Rc
            ;;
          # text/calendar goes through html-to-md --calendar, which emits
          # Markdown in the same dialect as the html path — highlight both.
          text/html|text/calendar)
            syntax=(
              -c 'set filetype=markdown conceallevel=2 concealcursor=nvic'
              -c 'lua pcall(vim.treesitter.start, 0, "markdown")'
              -c 'silent! source ${mailPagerLua}'
            )
            ;;
          *)
            syntax=(
              -c 'syntax enable'
              -c 'set filetype=mail'
            )
            ;;
          esac

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
          inputs.html-to-md.packages.${pkgs.stdenv.hostPlatform.system}.default
          mailOpen
          mailUnsubscribe
          mailPager
        ]
        ++ (with pkgs; [
          aerc
          chafa
          isync
          notmuch
        ]);

        # aerc takes the database path from notmuch config discovery, so point
        # that at the legacy ~/.notmuch-config we write rather than leaving
        sessionVariables.NOTMUCH_CONFIG = "${home}/.notmuch-config";

        file = {
          # nixpkgs' isync still reads ~/.mbsyncrc by default.
          ".mbsyncrc".text = mbsyncrc;
          # notmuch prefers this legacy path over XDG whenever it exists.
          ".notmuch-config".source = notmuchConfig;
        };
      };

      xdg.configFile = {
        "aerc/aerc.conf".text = ''
          [general]
          default-save-path=~/Downloads
          unsafe-accounts-conf=true
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
          text/plain=html-to-md --plain
          text/calendar=html-to-md --calendar
          image/*=chafa --format symbols

          [ui]
          border-char-vertical="│"
          border-char-horizontal="─"
          styleset-name=catppuccin-macchiato
          auto-mark-read=true
        '';
        "aerc/binds.conf".text = ''

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
          v = :mark -t<Enter>:next<Enter> # Toggle mark and move to next
          V = :mark -v<Enter> # Visual mode - toggle all
          <Space>v = :mark -a<Enter> # Mark all
          <Space>V = :unmark -a<Enter> # Unmark all
          <Space>x = :pipe -m -b /bin/sh -c 'aerc :delete'<Enter> # Delete marked
          <Space>X = :pipe -m -b /bin/sh -c 'aerc :read'<Enter> # Mark marked as read
          d = :delete<Enter> # Quick delete current
          D = :pipe -m aerc :delete<Enter> # Delete marked emails

          [view]
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
          <Space>l = :open-link<space> # Open link
          <Space>L = :copy-link<space> # Copy link
          <Space>? = :help keys<Enter> # Show key help

          [compose]
          <Tab> = :next-field<Enter> # Next field
          <S-Tab> = :prev-field<Enter> # Previous field
          <C-j> = :next-field<Enter> # Next field
          <C-k> = :prev-field<Enter> # Previous field

          [compose::editor]
          $noinherit = true
          $ex = <C-x>
          <Tab> = :next-field<Enter> # Next field
          <S-Tab> = :prev-field<Enter> # Previous field
          <C-j> = :next-field<Enter> # Next field
          <C-k> = :prev-field<Enter> # Previous field

          [compose::review]
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
        ".config/aerc/stylesets".src = "mail/stylesets";
      };

      # aerc fails with "No database found" and mbsync refuses a MaildirStore
      # whose Path is missing -- it does not mkdir its own Path -- so the tree
      # and an empty index have to exist before either runs.
      stubbe.setup.mail.script = ''
        mkdir -p ${lib.escapeShellArg "${maildir}/kontainer"} ${lib.escapeShellArg "${maildir}/gmail"}
        if [ ! -d ${lib.escapeShellArg "${maildir}/.notmuch"} ]; then
          ${lib.getExe pkgs.notmuch} --config="${home}/.notmuch-config" new --quiet || true
        fi
      '';

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
