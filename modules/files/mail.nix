_: {
  flake.modules.homeManager.filesMail =
    {
      self,
      pkgs,
      lib,
      config,
      homeLib,
      ...
    }:
    lib.mkIf config.features.desktop (
      let
        home = config.home.homeDirectory;
        maildir = "${home}/.local/share/mail";

        # mbsync's PassCmd runs at sync time. Re-using the same
        # sops-decrypted files aerc already reads keeps a single
        # source of truth for credentials.
        kontainerPw = config.sops.secrets.aerc-kontainer.path;
        gmailPw = config.sops.secrets.aerc-gmail.path;

        mbsyncrc = ''
          # ─── Kontainer (Exchange / IMAPS) ────────────────────────────
          IMAPAccount kontainer
          Host ex.konformit.com
          Port 993
          User abs@kontainer.com
          PassCmd "cat ${kontainerPw}"
          TLSType IMAPS
          AuthMechs LOGIN
          # Exchange's IMAP layer pipelines FETCH responses in a way that
          # trips mbsync's parser ("malformed FETCH response: unexpected
          # attribute"). Forcing one command at a time avoids the race.
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
          # Cap initial pull — server has ~5k INBOX messages, most years
          # old. Recent ~2k is plenty for local search; older mail still
          # lives on the server and can be reached on demand.
          MaxMessages 2000
          ExpireUnread no

          # ─── Gmail ───────────────────────────────────────────────────
          # Note: [Gmail]/All Mail mirrors every message ever, so we sync
          # only the inbox / sent / drafts. Archive (=[Gmail]/All Mail in
          # aerc) still works because aerc moves the maildir file into
          # ${maildir}/gmail/[Gmail]/All Mail/ on archive — mbsync then
          # pushes that copy up to the server next sync.
          IMAPAccount gmail
          Host imap.gmail.com
          Port 993
          User alexander.bugge.stage@gmail.com
          PassCmd "cat ${gmailPw}"
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
          # Cap [Gmail]/All Mail's initial pull so a long-lived account
          # doesn't drag in years of history on first sync.
          MaxMessages 5000
          ExpireUnread no
        '';

        notmuchConfig = ''
          [database]
          path=${maildir}

          [user]
          name=Alexander Bugge Stage
          primary_email=abs@kontainer.com
          other_email=alexander.bugge.stage@gmail.com

          # `unread` is the contract between notmuch and aerc: aerc strips
          # this tag when the user opens a message in the viewer, and
          # notmuch's synchronize_flags then renames the maildir file to
          # add the `S` flag — which mbsync propagates back to IMAP on
          # the next run. Nothing else marks messages as read.
          # `new` is a transient tag applied to every message indexed by
          # `notmuch new`; mail-sync notifies for the inbox ones then strips
          # it, so each new message produces exactly one desktop notification.
          [new]
          tags=unread;inbox;new;
          ignore=

          [search]
          exclude_tags=deleted;spam;

          # Bidirectional flag↔tag sync. Without this, aerc reading a
          # message would update notmuch but never reach the IMAP server.
          [maildir]
          synchronize_flags=true
        '';

        # Tagging used to live in a notmuch post-new hook, but the hook
        # dir is inside ${maildir}/.notmuch/ which notmuch creates
        # itself — home-manager refuses to symlink files into a
        # directory it doesn't own, so the hook never landed on disk.
        # Inlining here means the tags get applied on every sync,
        # regardless of how home-manager activation went.
        #
        # path: (recursive) and folder: (exact) instead of regex —
        # regex delimiters can't contain spaces, which breaks on
        # Gmail's `[Gmail]/All Mail`.
        mailSync = pkgs.writeShellApplication {
          name = "mail-sync";
          runtimeInputs = [
            pkgs.isync
            pkgs.notmuch
            pkgs.util-linux # flock
            pkgs.libnotify # notify-send
            pkgs.jq # parse notmuch search JSON
          ];
          text = ''
            # Sync every channel by default; pass channel name(s) to limit.
            # Run channels independently so one account's outage (auth,
            # network, server-side flake-out) doesn't black-hole the other.
            if [ "$#" -eq 0 ]; then
              channels=(kontainer gmail)
            else
              channels=("$@")
            fi

            # mail-sync is invoked from three independent schedulers:
            # the systemd timer (all channels every 30s), aerc's per-account
            # check-mail-cmd, and the user from CLI. Without serialization
            # they collide on mbsync's per-channel SyncState lock, leaving
            # half-synced folders in "cannot be opened anymore" state.
            # Per-channel flock with -E 75 distinguishes "lock busy"
            # (skip cleanly) from "mbsync genuinely failed" (report).
            lock_dir="''${XDG_RUNTIME_DIR:-/tmp}"
            mkdir -p "$lock_dir"

            failed=()
            for ch in "''${channels[@]}"; do
              rc=0
              flock -n -E 75 "$lock_dir/mail-sync-$ch.lock" mbsync "$ch" || rc=$?
              case "$rc" in
                0)
                  ;;
                75)
                  echo "mail-sync: $ch already syncing elsewhere, skipping" >&2
                  ;;
                *)
                  echo "mail-sync: mbsync $ch failed (exit $rc)" >&2
                  failed+=("$ch")
                  ;;
              esac
            done

            # Always reindex — partial syncs are still worth indexing so
            # aerc reflects whatever did land. --quiet is a `new`
            # subcommand flag (not top-level), suppresses per-message
            # progress; the "Note: Ignoring non-mail file" lines come
            # from mbsync, not notmuch, so they're unaffected.
            notmuch new --quiet || true

            notmuch tag +kontainer -- 'path:kontainer/** and not tag:kontainer' || true
            notmuch tag +gmail     -- 'path:gmail/**     and not tag:gmail'     || true
            notmuch tag -inbox -- 'tag:inbox and not folder:kontainer/INBOX and not folder:gmail/INBOX' || true

            # Desktop notifications for newly-arrived inbox mail. The transient
            # `new` tag (from notmuch's [new] tags=) marks everything indexed
            # this run; notify for the inbox ones with sender + subject, then
            # strip it so each message notifies exactly once. A bulk initial
            # sync collapses to a single summary instead of a flood. notify-send
            # talks to wayle over the session bus; guarded with || true so a
            # missing bus (e.g. headless run) never fails the sync.
            new_count=$(notmuch count 'tag:new and tag:inbox')
            if [ "$new_count" -gt 0 ]; then
              if [ "$new_count" -le 10 ]; then
                notmuch search --format=json --output=summary --sort=newest-first 'tag:new and tag:inbox' \
                  | jq -r '.[] | [.authors, .subject] | @tsv' \
                  | while IFS=$'\t' read -r from subject; do
                      notify-send -a mail -i mail-message-new-symbolic \
                        "''${from:-Unknown sender}" "''${subject:-(no subject)}" || true
                    done
              else
                notify-send -a mail -i mail-message-new-symbolic \
                  "New mail" "$new_count new messages" || true
              fi
            fi
            notmuch tag -new -- tag:new || true

            if [ ''${#failed[@]} -gt 0 ]; then
              echo "mail-sync: failed channels: ''${failed[*]}" >&2
              exit 1
            fi
          '';
        };

        # maildir-account-path scopes each tab's dirlist (and the
        # folder names used by copy-to/postpone/archive) to that
        # account's subtree under maildir-store. Without it, aerc
        # enumerates the shared maildir root and every tab shows
        # both accounts' folders in the sidebar.
        aercAccountsConf = ''
          [kontainer]
          source=notmuch://${maildir}
          maildir-store=${maildir}
          maildir-account-path=kontainer
          query-map=${home}/.config/aerc/queries-kontainer
          exclude-tags=deleted,spam
          default=INBOX
          folders=INBOX,Sent
          from=Alexander Bugge Stage <abs@kontainer.com>
          outgoing=smtp+login://abs@kontainer.com@ex.konformit.com:587
          outgoing-cred-cmd=cat ${kontainerPw}
          copy-to=Sent
          postpone=Drafts
          archive=Archive
          check-mail-cmd=${mailSync}/bin/mail-sync kontainer
          check-mail=30s

          [gmail]
          source=notmuch://${maildir}
          maildir-store=${maildir}
          maildir-account-path=gmail
          query-map=${home}/.config/aerc/queries-gmail
          exclude-tags=deleted,spam,trash
          default=INBOX
          folders=INBOX,Sent
          from=Alexander Bugge Stage <alexander.bugge.stage@gmail.com>
          outgoing=smtp+plain://alexander.bugge.stage@gmail.com@smtp.gmail.com:587
          outgoing-cred-cmd=cat ${gmailPw}
          copy-to=[Gmail]/Sent Mail
          postpone=[Gmail]/Drafts
          archive=[Gmail]/All Mail
          check-mail-cmd=${mailSync}/bin/mail-sync gmail
          check-mail=30s
        '';

        # query-map: virtual folder name → notmuch query. aerc opens the
        # named folder by running its query against the local index.
        # Sent is virtualised so the gmail sidebar shows "Sent" instead
        # of "[Gmail]/Sent Mail".
        queriesKontainer = ''
          INBOX = tag:kontainer and tag:inbox
          Sent  = folder:/^kontainer\/Sent$/
        '';

        queriesGmail = ''
          INBOX = tag:gmail and tag:inbox
          Sent  = folder:"gmail/[Gmail]/Sent Mail"
        '';
      in
      {
        # Same sops-decrypted password files the IMAP credentials lived
        # in before. mbsync's PassCmd and aerc's outgoing-cred-cmd both
        # read these.
        sops.secrets.aerc-gmail = homeLib.mkBinarySecret {
          name = "aerc-gmail";
          path = "${home}/.config/aerc/passwords/gmail";
        };
        sops.secrets.aerc-kontainer = homeLib.mkBinarySecret {
          name = "aerc-kontainer";
          path = "${home}/.config/aerc/passwords/kontainer";
        };

        home.packages = [ mailSync ];

        home.file = {
          ".w3m".source = self + "/src/w3m";

          # mbsync still reads ~/.mbsyncrc by default in nixpkgs' isync.
          ".mbsyncrc".text = mbsyncrc;

          # notmuch reads ~/.notmuch-config (legacy path) regardless of XDG
          # if the file exists — keep it explicit.
          ".notmuch-config".text = notmuchConfig;
        };

        xdg.configFile = {
          "aerc/accounts.conf".text = aercAccountsConf;
          "aerc/queries-kontainer".text = queriesKontainer;
          "aerc/queries-gmail".text = queriesGmail;
        };

        # Periodic sync every 30s so notifications fire within the
        # waybar refresh window. mbsync STATUS-only round-trips are
        # cheap (~1-2s) when nothing changed; the lock file in
        # ~/.mbsync prevents concurrent runs from piling up.
        systemd.user.services.mail-sync = {
          Unit = {
            Description = "Sync IMAP -> local maildir + reindex with notmuch";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${mailSync}/bin/mail-sync";
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };
        systemd.user.timers.mail-sync = {
          Unit.Description = "Periodic mail sync";
          Timer = {
            OnBootSec = "30s";
            OnUnitActiveSec = "30s";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      }
    );
}
