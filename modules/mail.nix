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
      notmuchMcp = inputs.notmuch-mcp.packages.${pkgs.stdenv.hostPlatform.system}.default;

      maildirBase = ".local/share/mail";
      maildir = "${config.home.homeDirectory}/${maildirBase}";
      realName = "Alexander Bugge Stage";

      accountNames = [
        "kontainer"
        "gmail"
        "stubbe"
      ];
      secretName = account: "mail-${account}";
      passwordCommand = account: "cat ${config.sops.secrets.${secretName account}.path}";

      # Not a notmuch post-new hook: that hook dir lives inside .notmuch/, which
      # notmuch creates itself and home-manager will not symlink into, so the
      # tagging runs here after `notmuch new`. path: globs, not folder: regex:
      # regex delimiters cannot contain spaces, which breaks on `[Gmail]/All Mail`.
      mailSync = pkgs.stubbe.bashApp {
        name = "mail-sync";
        runtimeInputs = with pkgs; [
          isync
          notmuch
          util-linux # flock
        ];
        text = ''
          accounts=(${lib.escapeShellArgs accountNames})
          if [ "$#" -eq 0 ]; then
            channels=("''${accounts[@]}")
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

          notmuch new --quiet

          ${lib.concatMapStrings (account: ''
            notmuch tag +${account} -- 'path:${account}/** and not tag:${account}'
          '') accountNames}
          notmuch tag -inbox -- 'tag:inbox and ${
            lib.concatStringsSep " and " (map (account: "not folder:${account}/INBOX") accountNames)
          }'

          if [ ''${#failed[@]} -gt 0 ]; then
            echo "mail-sync: failed channels: ''${failed[*]}" >&2
            exit 1
          fi
        '';
      };

      mailboxes = {
        kontainer = {
          archive = "Archive";
          folders = [
            {
              name = "INBOX";
              query = "tag:kontainer and tag:inbox";
            }
            {
              name = "Sent";
              query = "folder:/^kontainer\\/Sent$/";
            }
            {
              name = "Junk";
              query = ''folder:"kontainer/Junk Email"'';
            }
          ];
        };
        gmail = {
          archive = "[Gmail]/All Mail";
          folders = [
            {
              name = "INBOX";
              query = "tag:gmail and tag:inbox";
            }
            {
              name = "Sent";
              query = ''folder:"gmail/[Gmail]/Sent Mail"'';
            }
            {
              name = "Junk";
              query = ''folder:"gmail/[Gmail]/Spam"'';
            }
          ];
        };
        stubbe = {
          archive = "Archive";
          folders = [
            {
              name = "INBOX";
              query = "tag:stubbe and tag:inbox";
            }
            {
              name = "Sent";
              query = ''folder:"stubbe/Sent Items"'';
            }
            {
              name = "Junk";
              query = ''folder:"stubbe/Junk Mail"'';
            }
          ];
        };
      };

      emailNvimAccounts = map (
        name:
        let
          account = config.accounts.email.accounts.${name};
        in
        {
          name = lib.toSentenceCase name;
          maildir = account.maildir.path;
          from = "${account.realName} <${account.address}>";
          addresses = [ account.address ] ++ account.aliases;
          inherit (account.folders)
            inbox
            sent
            drafts
            trash
            ;
          inherit (mailboxes.${name}) archive folders;
        }
        // lib.optionalAttrs (account.signature.text != "") { signature = account.signature.text; }
      ) accountNames;

      mailOpen = pkgs.stubbe.bashApp {
        name = "mail-open";
        runtimeInputs = [ pkgs.jq ];
        text = ''
          APP_ID="dev.stubbe.mail"

          spawn_term() {
            exec ${config.stubbe.paths.terminal} --class="$APP_ID" -e nvim -c "$1"
          }

          if [ "$#" -gt 0 ]; then
            spawn_term "EmailOpen $*"
          fi

          if [[ "$XDG_CURRENT_DESKTOP" == "lys-wm" ]] && command -v lys-wmctl &> /dev/null; then
            id=$(lys-wmctl windows | jq -r --arg c "$APP_ID" '.[] | select(.app_id == $c) | .id' | head -n1)
            if [[ -n "$id" ]]; then
              ws=$(lys-wmctl workspaces | jq -r '.[] | select(.focused) | .id')
              lys-wmctl dispatch focuswindow "$id"
              lys-wmctl dispatch movetoworkspace "$ws"
              lys-wmctl dispatch focuswindow "$id"
            else
              spawn_term Email
            fi
          else
            spawn_term Email
          fi
        '';
      };

    in
    lib.mkIf config.features.desktop {
      sops.secrets = lib.listToAttrs (
        map (
          account: lib.nameValuePair (secretName account) (pkgs.stubbe.secret { name = secretName account; })
        ) accountNames
      );

      # One accounts.email tree feeding home-manager's mbsync, notmuch and msmtp
      # modules. Account names are the mbsync channel names the wrapper script
      # relies on. Side effects outside mail: home-manager's git module renders
      # a sendemail section per smtp account.
      accounts.email = {
        maildirBasePath = maildirBase;

        accounts = {
          kontainer = {
            primary = true;
            address = "abs@kontainer.com";
            inherit realName;
            userName = "abs@kontainer.com";
            passwordCommand = passwordCommand "kontainer";
            imapnotify = {
              enable = true;
              boxes = [ "INBOX" ];
              onNotify = "${lib.getExe mailSync} kontainer";
            };
            folders = {
              inbox = "INBOX";
              trash = "Deleted Items";
            };
            imap = {
              host = "ex.konformit.com";
              port = 993;
            };
            smtp = {
              host = "ex.konformit.com";
              port = 587;
              tls.useStartTls = true;
            };
            mbsync = {
              enable = true;
              create = "both";
              expunge = "both";
              patterns = [
                "INBOX"
                "Sent"
                "Drafts"
                "Archive"
                "Junk Email"
                "Deleted Items"
              ];
              extraConfig.account = {
                AuthMechs = "LOGIN";
                PipelineDepth = 1;
              };
              extraConfig.channel = {
                MaxMessages = 2000;
                ExpireUnread = "no";
              };
            };
            notmuch.enable = true;
            msmtp = {
              enable = true;
              extraConfig.auth = "login";
            };
          };
          gmail = {
            address = "alexander.bugge.stage@gmail.com";
            inherit realName;
            userName = "alexander.bugge.stage@gmail.com";
            passwordCommand = passwordCommand "gmail";
            imapnotify = {
              enable = true;
              boxes = [ "INBOX" ];
              onNotify = "${lib.getExe mailSync} gmail";
            };
            folders = {
              inbox = "INBOX";
              sent = "[Gmail]/Sent Mail";
              drafts = "[Gmail]/Drafts";
              trash = "[Gmail]/Bin";
            };
            imap = {
              host = "imap.gmail.com";
              port = 993;
            };
            smtp = {
              host = "smtp.gmail.com";
              port = 587;
              tls.useStartTls = true;
            };
            mbsync = {
              enable = true;
              create = "both";
              expunge = "both";
              patterns = [
                "INBOX"
                "[Gmail]/Sent Mail"
                "[Gmail]/Drafts"
                "[Gmail]/All Mail"
                "[Gmail]/Spam"
                "[Gmail]/Bin"
              ];
              extraConfig = {
                account.AuthMechs = "LOGIN";
                channel = {
                  MaxMessages = 5000;
                  ExpireUnread = "no";
                };
              };
            };
            notmuch.enable = true;
            msmtp.enable = true;
          };
          stubbe = {
            address = "abs@stubbe.dev";
            aliases = [
              "hello@stubbe.dev"
              "admin@stubbe.dev"
            ];
            inherit realName;
            userName = "admin@stubbe.dev";
            passwordCommand = passwordCommand "stubbe";
            imapnotify = {
              enable = true;
              boxes = [ "INBOX" ];
              onNotify = "${lib.getExe mailSync} stubbe";
            };
            folders = {
              inbox = "INBOX";
              sent = "Sent Items";
              drafts = "Drafts";
              trash = "Deleted Items";
            };
            imap = {
              host = "mail.stubbe.dev";
              port = 993;
            };
            smtp = {
              host = "mail.stubbe.dev";
              port = 465;
            };
            mbsync = {
              enable = true;
              create = "both";
              expunge = "both";
              patterns = [
                "INBOX"
                "Sent Items"
                "Drafts"
                "Archive"
                "Junk Mail"
                "Deleted Items"
              ];
              extraConfig.account.AuthMechs = "LOGIN";
            };
            notmuch.enable = true;
            msmtp.enable = true;
          };
        };
      };

      programs.mbsync.enable = true;
      services.imapnotify.enable = true;
      programs.msmtp.enable = true;

      stubbe.mcpServers.notmuch-mcp = {
        type = "stdio";
        command = lib.getExe notmuchMcp;
        args = [ ];
      };

      # Identity and database.path come from accounts.email; search exclude
      # deleted;spam (stateVersion default) and new.ignore .uidvalidity/
      # .mbsyncstate (added by the mbsync module) match the old config.
      programs.notmuch = {
        enable = true;

        # Pinned (they are also notmuch's own defaults) because the read-marking
        # contract leans on them: email.nvim strips the unread tag on open,
        # synchronize_flags renames the file to add `S`, and mbsync propagates
        # that to IMAP. Nothing else marks mail as read.
        settings = {
          maildir.synchronize_flags = true;
          new.tags = [
            "unread"
            "inbox"
          ];
        };
      };

      home.packages = [
        mailSync
        inputs.html-to-md.packages.${pkgs.stdenv.hostPlatform.system}.default
        notmuchMcp
        mailOpen
      ];

      xdg.configFile."email.nvim/accounts.json".text = builtins.toJSON emailNvimAccounts;

      # notmuch clients fail with "No database found" before the first sync, so
      # an empty index has to exist up front; the maildir tree itself is covered by
      # home-manager's createMaildir activation (programs.mbsync), which runs
      # before writeBoundary and therefore before this step.
      stubbe.setup.mail.script = ''
        if [ ! -d ${lib.escapeShellArg "${maildir}/.notmuch"} ]; then
          ${lib.getExe pkgs.notmuch} --config="${config.xdg.configHome}/notmuch/default/config" new --quiet
        fi
      '';

      systemd.user = {
        services.mail-sync = {
          Unit = {
            Description = "Sync IMAP -> local maildir + reindex with notmuch";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe mailSync;
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };
        timers.mail-sync = {
          Unit.Description = "Periodic mail sync, behind the IMAP IDLE watchers";
          Timer = {
            OnStartupSec = "30s";
            OnUnitActiveSec = "5min";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
