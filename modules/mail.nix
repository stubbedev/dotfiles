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

      # glow reads glamour's own JSON dialect; this is catppuccin's macchiato
      # theme, matching the aerc styleset in mail/stylesets.
      glowStyle = pkgs.stubbe.gen.json "glow-catppuccin-macchiato.json" {
        document = {
          block_prefix = "\n";
          block_suffix = "\n";
          color = "#cad3f5";
          margin = 2;
        };
        block_quote = {
          indent = 1;
          indent_token = "│ ";
        };
        list.level_indent = 2;
        heading = {
          block_suffix = "\n";
          color = "#cad3f5";
          bold = true;
        };
        h1 = {
          prefix = "▓▓▓ ";
          suffix = " ";
          color = "#ed8796";
          bold = true;
        };
        h2 = {
          prefix = "▓▓▓▓ ";
          color = "#f5a97f";
        };
        h3 = {
          prefix = "▓▓▓▓▓ ";
          color = "#eed49f";
        };
        h4 = {
          prefix = "▓▓▓▓▓▓ ";
          color = "#a6da95";
        };
        h5 = {
          prefix = "▓▓▓▓▓▓▓ ";
          color = "#7dc4e4";
        };
        h6 = {
          prefix = "▓▓▓▓▓▓▓▓ ";
          color = "#b7bdf8";
        };
        strikethrough.crossed_out = true;
        emph.italic = true;
        strong.bold = true;
        hr = {
          color = "#6e738d";
          format = "\n────────\n";
        };
        item.block_prefix = "• ";
        enumeration.block_prefix = ". ";
        task = {
          ticked = "[✓] ";
          unticked = "[ ] ";
        };
        # glamour prints the href next to the label and wraps both in the same
        # OSC 8 hyperlink. The label alone is clickable in alacritty, so blank
        # the href token out with an empty template and keep just the label.
        link = {
          color = "#8aadf4";
          underline = true;
          format = "{{\"\"}}";
        };
        link_text = {
          color = "#b7bdf8";
          bold = true;
        };
        image = {
          color = "#8aadf4";
          underline = true;
        };
        image_text = {
          color = "#b7bdf8";
          format = "Image: {{.text}} →";
        };
        code = {
          prefix = " ";
          suffix = " ";
          color = "#ee99a0";
          background_color = "#1e2030";
        };
        code_block = {
          color = "#1e2030";
          margin = 2;
          chroma = {
            text.color = "#cad3f5";
            error = {
              color = "#cad3f5";
              background_color = "#ed8796";
            };
            comment.color = "#6e738d";
            comment_preproc.color = "#8aadf4";
            keyword.color = "#c6a0f6";
            keyword_reserved.color = "#c6a0f6";
            keyword_namespace.color = "#eed49f";
            keyword_type.color = "#eed49f";
            operator.color = "#91d7e3";
            punctuation.color = "#939ab7";
            name.color = "#b7bdf8";
            name_builtin.color = "#f5a97f";
            name_tag.color = "#c6a0f6";
            name_attribute.color = "#eed49f";
            name_class.color = "#eed49f";
            name_constant.color = "#eed49f";
            name_decorator.color = "#f5bde6";
            name_function.color = "#8aadf4";
            literal_number.color = "#f5a97f";
            literal_string.color = "#a6da95";
            literal_string_escape.color = "#f5bde6";
            generic_deleted.color = "#ed8796";
            generic_inserted.color = "#a6da95";
            generic_emph = {
              color = "#cad3f5";
              italic = true;
            };
            generic_strong = {
              color = "#cad3f5";
              bold = true;
            };
            generic_subheading.color = "#91d7e3";
            background.background_color = "#1e2030";
          };
        };
        table = {
          center_separator = "┼";
          column_separator = "│";
          row_separator = "─";
        };
        definition_description.block_prefix = "\n🠶 ";
      };

      mailPager = pkgs.stubbe.bashApp {
        name = "mail-pager";
        runtimeInputs = with pkgs; [
          glow
          less
          coreutils
        ];
        text = ''
          if [[ "''${AERC_MIME_TYPE:-}" == image/* ]]; then
            exec less -Rc
          fi

          # glow takes its width and colour profile from stdout, which here is
          # the pipe into less: without these it wraps at 80 and drops every
          # escape. The pty is still on /dev/tty, so read the width from there.
          cols=$(stty size </dev/tty 2>/dev/null | cut -d' ' -f2) || true

          # less, not glow's own output alone: aerc resizes the pager pty after
          # the child has written, and a finished process cannot repaint, which
          # left short mails pinned to the bottom of the pane until a scroll
          # forced a redraw. less redraws on SIGWINCH, and -c draws from the top.
          # 2>/dev/null is load-bearing: with a tty on stderr glow probes it for
          # the background colour and blocks on the reply, which aerc's terminal
          # never sends -- ten seconds of blank pane per mail.
          COLORTERM=truecolor glow -s ${glowStyle} -w "''${cols:-100}" - 2>/dev/null | less -Rc
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
