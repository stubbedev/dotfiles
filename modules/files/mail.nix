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
    lib.mkIf config.features.desktop
      (
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
            [new]
            tags=unread;inbox;
            ignore=

            [search]
            exclude_tags=deleted;spam;

            # Bidirectional flag↔tag sync. Without this, aerc reading a
            # message would update notmuch but never reach the IMAP server.
            [maildir]
            synchronize_flags=true
          '';

          # post-new fires after `notmuch new`. Tag by maildir path so each
          # account's queries can filter to its own mail; strip the default
          # `inbox` tag from anything not actually in an INBOX folder so
          # archive/sent/drafts don't pollute the inbox view.
          # Queries use notmuch's `path:` (recursive) and `folder:` (exact)
          # operators rather than `folder:/regex/` — regex delimiters can't
          # contain spaces, which breaks on Gmail's `[Gmail]/All Mail`.
          postNewHook = pkgs.writeShellScript "notmuch-post-new" ''
            set -eu
            export PATH="${pkgs.notmuch}/bin:$PATH"

            notmuch tag +kontainer -- 'path:kontainer/** and not tag:kontainer'
            notmuch tag +gmail     -- 'path:gmail/**     and not tag:gmail'

            notmuch tag -inbox -- 'tag:inbox and not folder:kontainer/INBOX and not folder:gmail/INBOX'
          '';

          mailSync = pkgs.writeShellApplication {
            name = "mail-sync";
            runtimeInputs = [
              pkgs.isync
              pkgs.notmuch
            ];
            text = ''
              # Sync every channel by default; pass channel name(s) to limit.
              if [ "$#" -eq 0 ]; then
                mbsync -a
              else
                mbsync "$@"
              fi
              notmuch new --quiet
            '';
          };

          aercAccountsConf = ''
            [kontainer]
            source=notmuch://${maildir}
            maildir-store=${maildir}
            query-map=${home}/.config/aerc/queries-kontainer
            exclude-tags=deleted,spam
            default=INBOX
            from=Alexander Bugge Stage <abs@kontainer.com>
            outgoing=smtp+login://abs@kontainer.com@ex.konformit.com:587
            outgoing-cred-cmd=cat ${kontainerPw}
            copy-to=kontainer/Sent
            postpone=kontainer/Drafts
            archive=kontainer/Archive
            check-mail-cmd=${mailSync}/bin/mail-sync kontainer
            check-mail=5m

            [gmail]
            source=notmuch://${maildir}
            maildir-store=${maildir}
            query-map=${home}/.config/aerc/queries-gmail
            exclude-tags=deleted,spam,trash
            default=INBOX
            from=Alexander Bugge Stage <alexander.bugge.stage@gmail.com>
            outgoing=smtp+plain://alexander.bugge.stage@gmail.com@smtp.gmail.com:587
            outgoing-cred-cmd=cat ${gmailPw}
            copy-to=gmail/[Gmail]/Sent Mail
            postpone=gmail/[Gmail]/Drafts
            archive=gmail/[Gmail]/All Mail
            check-mail-cmd=${mailSync}/bin/mail-sync gmail
            check-mail=5m
          '';

          # query-map: virtual folder name → notmuch query. aerc opens the
          # named folder by running its query against the local index.
          queriesKontainer = ''
            INBOX   = tag:kontainer and tag:inbox
            Sent    = folder:/^kontainer\/Sent$/
            Drafts  = folder:/^kontainer\/Drafts$/
            Archive = folder:/^kontainer\/Archive$/
          '';

          queriesGmail = ''
            INBOX               = tag:gmail and tag:inbox
            [Gmail]/Sent Mail   = folder:"gmail/[Gmail]/Sent Mail"
            [Gmail]/Drafts      = folder:"gmail/[Gmail]/Drafts"
            [Gmail]/All Mail    = folder:"gmail/[Gmail]/All Mail"
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

          home.file.".w3m".source = self + "/src/w3m";

          # mbsync still reads ~/.mbsyncrc by default in nixpkgs' isync.
          home.file.".mbsyncrc".text = mbsyncrc;

          # notmuch reads ~/.notmuch-config (legacy path) regardless of XDG
          # if the file exists — keep it explicit.
          home.file.".notmuch-config".text = notmuchConfig;

          # The hooks dir lives inside the notmuch DB. notmuch creates
          # ${maildir}/.notmuch on first run; we only own the post-new file.
          home.file.".local/share/mail/.notmuch/hooks/post-new" = {
            source = postNewHook;
            executable = true;
          };

          xdg.configFile."aerc/accounts.conf".text = aercAccountsConf;
          xdg.configFile."aerc/queries-kontainer".text = queriesKontainer;
          xdg.configFile."aerc/queries-gmail".text = queriesGmail;

          # Periodic sync: every 5 minutes after the last successful run.
          # OnBootSec=1m kicks the first sync soon after login; Persistent
          # makes us catch up if the laptop was suspended past the window.
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
              OnBootSec = "1m";
              OnUnitActiveSec = "5m";
              Persistent = true;
              RandomizedDelaySec = "30s";
            };
            Install.WantedBy = [ "timers.target" ];
          };
        }
      );
}
