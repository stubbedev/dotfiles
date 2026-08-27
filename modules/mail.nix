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

      notmuchConfig = ''
        [database]
        path=${maildir}

        [user]
        name=Alexander Bugge Stage
        primary_email=abs@kontainer.com
        other_email=alexander.bugge.stage@gmail.com

        # `unread` is the contract between notmuch and aerc: aerc strips this
        # tag when the user opens a message, notmuch's synchronize_flags then
        # renames the maildir file to add the `S` flag, and mbsync propagates
        # that back to IMAP on the next run. Nothing else marks mail as read.
        [new]
        tags=unread;inbox;
        ignore=

        [search]
        exclude_tags=deleted;spam;

        # Bidirectional flag↔tag sync. Without this, aerc reading a message
        # would update notmuch but never reach the IMAP server.
        [maildir]
        synchronize_flags=true
      '';

      # Tagging used to live in a notmuch post-new hook, but the hook dir is
      # inside ${maildir}/.notmuch/ which notmuch creates itself —
      # home-manager refuses to symlink into a directory it does not own, so
      # the hook never landed. Inlining here applies the tags on every sync
      # regardless of how activation went.
      #
      # path: (recursive) and folder: (exact) rather than regex — regex
      # delimiters cannot contain spaces, which breaks on `[Gmail]/All Mail`.
      mailSync = pkgs.writeShellApplication {
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
      accountsConf = ''
        [kontainer]
        source=notmuch://
        maildir-account-path=kontainer
        query-map=${home}/.config/aerc/queries-kontainer
        exclude-tags=deleted,spam
        default=INBOX
        folders=INBOX,Sent
        from=Alexander Bugge Stage <abs@kontainer.com>
        outgoing=smtp+login://abs@kontainer.com@ex.konformit.com:587
        outgoing-cred-cmd=cat ${passwords.kontainer}
        copy-to=Sent
        postpone=Drafts
        archive=Archive
        check-mail-cmd=${lib.getExe mailSync} kontainer
        check-mail=30s

        [gmail]
        source=notmuch://
        maildir-account-path=gmail
        query-map=${home}/.config/aerc/queries-gmail
        exclude-tags=deleted,spam,trash
        default=INBOX
        folders=INBOX,Sent
        from=Alexander Bugge Stage <alexander.bugge.stage@gmail.com>
        outgoing=smtp+plain://alexander.bugge.stage@gmail.com@smtp.gmail.com:587
        outgoing-cred-cmd=cat ${passwords.gmail}
        copy-to=[Gmail]/Sent Mail
        postpone=[Gmail]/Drafts
        archive=[Gmail]/All Mail
        check-mail-cmd=${lib.getExe mailSync} gmail
        check-mail=30s
      '';

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
          (pkgs.stubbe.scriptBin {
            name = "mail-open";
            source = "src/mail/open-mail";
            vars.TERM = config.stubbe.paths.terminal;
          })
          (pkgs.stubbe.scriptBin {
            name = "mail-unsubscribe";
            source = "src/mail/unsubscribe";
          })
          (pkgs.stubbe.scriptBin {
            name = "mail-pager";
            source = "src/mail/mail-pager";
            # scriptBin emits a lone bin/mail-pager, so the pager's Lua half
            # has no sibling to find at runtime — point at it in the store
            # instead of resolving relative to $0.
            vars.PAGER_LUA = pkgs.stubbe.file "src/mail/mail-pager.lua";
          })
        ]
        ++ (with pkgs; [
          # The client itself, and the address-book/calendar tooling beside it.
          aerc
          khard
          vdirsyncer
          mailutils
          msmtp
          w3m
          pandoc
          lynx
          chafa
          catimg
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
          ".notmuch-config".text = notmuchConfig;
        };
      };

      xdg.configFile = {
        "aerc/aerc.conf".source = pkgs.stubbe.file "src/mail/aerc.conf";
        "aerc/binds.conf".source = pkgs.stubbe.file "src/mail/binds.conf";
        "aerc/accounts.conf".text = accountsConf;
        "aerc/queries-kontainer".text = queries.kontainer;
        "aerc/queries-gmail".text = queries.gmail;
      };

      stubbe.mutable = {
        # aerc rewrites nothing here, but stylesets are the thing you iterate
        # on by eye — link the checkout so an edit shows on the next launch.
        ".config/aerc/stylesets".src = "mail/stylesets";
        # w3m writes bookmarks, cookies and history into ~/.w3m, so the
        # directory itself cannot be a store symlink; install just our config
        # file and leave the rest of the directory to w3m.
        ".w3m/config" = {
          src = "mail/w3m-config";
          method = "copy";
        };
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
