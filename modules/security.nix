{ inputs, ... }:
{
  flake.modules.nixos.security =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.lys-secrets.nixosModules.default ];

      security.sudo = {
        wheelNeedsPassword = true;

        execWheelOnly = true;

        extraConfig = ''
          Defaults pwfeedback
        '';
      };

      services.lys-secrets = lib.mkIf config.stubbe.userFeatures.desktop {
        enable = true;
        package = pkgs.lys-secrets;
      };

      programs.gnupg.agent = {
        enable = true;
        pinentryPackage = pkgs.pinentry-curses;
      };
    };

  flake.modules.nixos.polkit =
    { config, lib, ... }:
    let
      username = config.host.primaryUser;
    in
    {
      security.polkit.enable = true;

      environment.etc = {
        "polkit-1/rules.d/52-power-management.rules".text =
          let
            verbs = [
              "reboot"
              "reboot-ignore-inhibit"
              "power-off"
              "power-off-ignore-inhibit"
              "halt"
              "halt-ignore-inhibit"
              "suspend"
              "suspend-ignore-inhibit"
              "hibernate"
              "hibernate-ignore-inhibit"
              "hybrid-sleep"
              "suspend-then-hibernate"
            ];
            actions = map (v: "org.freedesktop.login1.${v}") (
              verbs
              ++ map (v: "${v}-multiple-sessions") (builtins.filter (v: !lib.hasSuffix "-ignore-inhibit" v) verbs)
            );
          in
          ''
            polkit.addRule(function(action, subject) {
              if (action.id.indexOf("org.freedesktop.login1.") !== 0) {
                return;
              }

              var allowed = ${builtins.toJSON (lib.genAttrs actions (_: true))};

              if (!allowed[action.id]) {
                return;
              }

              if (subject.user !== "${username}" || !subject.local || !subject.active) {
                return;
              }

              return polkit.Result.YES;
            });
          '';
      };
    };

  flake.modules.homeManager.security =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      pamFiles = [
        "/etc/pam.d/login"
        "/etc/pam.d/ly"
        "/etc/pam.d/lightdm"
        "/etc/pam.d/gdm"
      ];

      copyKeyringSecrets =
        pkgs.writers.writePython3Bin "copy-keyring-secrets"
          {
            libraries = with pkgs.python3Packages; [
              secretstorage
              jeepney
            ];
          }
          ''
            import hashlib
            import sys
            import time

            import secretstorage
            from jeepney import DBusAddress, new_method_call
            from jeepney.io.blocking import open_dbus_connection
            from jeepney.wrappers import DBusErrorResponse
            from secretstorage.collection import Collection

            SERVICE = "org.freedesktop.secrets"
            COLLECTIONS = "/org/freedesktop/secrets/collection/"
            SOURCE_LOCKED = 3


            def wait_for_service(connection):
                bus = DBusAddress(
                    "/org/freedesktop/DBus",
                    bus_name="org.freedesktop.DBus",
                    interface="org.freedesktop.DBus",
                )
                for _ in range(100):
                    message = new_method_call(bus, "NameHasOwner", "s", (SERVICE,))
                    if connection.send_and_get_reply(message).body[0]:
                        return
                    time.sleep(0.1)
                sys.exit(f"{SERVICE} never appeared on the bus")


            def wait_for_login_collection(connection):
                for _ in range(100):
                    try:
                        return Collection(connection, COLLECTIONS + "login")
                    except DBusErrorResponse:
                        time.sleep(0.1)
                sys.exit("lys-secrets never created the login collection")


            def digest(item):
                return hashlib.sha256(item.get_secret()).hexdigest()


            def main(source_address, target_address):
                source = open_dbus_connection(bus=source_address)
                target = open_dbus_connection(bus=target_address)
                wait_for_service(source)
                wait_for_service(target)

                login = wait_for_login_collection(target)
                copied = 0
                skipped = []
                for collection in secretstorage.get_all_collections(source):
                    path = collection.collection_path
                    if path == COLLECTIONS + "session":
                        continue
                    if collection.is_locked():
                        if path == COLLECTIONS + "login":
                            sys.exit(SOURCE_LOCKED)
                        skipped.append(collection.get_label())
                        continue
                    for item in collection.get_all_items():
                        attributes = item.get_attributes()
                        created = login.create_item(
                            item.get_label(),
                            attributes,
                            item.get_secret(),
                            replace=True,
                            content_type=item.get_secret_content_type(),
                        )
                        if digest(created) != digest(item):
                            sys.exit(f"copy of {item.get_label()!r} does not match")
                        print(f"  copied: {item.get_label()}")
                        copied += 1

                print(f"keyring-migrate: {copied} secrets copied and verified")
                if skipped:
                    names = ", ".join(skipped)
                    print(f"keyring-migrate: NOT copied, still locked: {names}")


            main(sys.argv[1], sys.argv[2])
          '';

      keyringMigrate = pkgs.stubbe.bashApp {
        name = "keyring-migrate";
        runtimeInputs = with pkgs; [
          coreutils
          dbus
          gnome-keyring
          lys-secrets
          copyKeyringSecrets
        ];
        text = ''
          user=$(id -un)
          data="''${XDG_DATA_HOME:-$HOME/.local/share}"
          source_keyring="$data/keyrings/login.keyring"
          final_dir="$data/lys-secrets"

          if [ ! -f "$source_keyring" ]; then
            echo "keyring-migrate: no gnome-keyring login keyring at $source_keyring, nothing to copy."
            exit 0
          fi
          if [ -e "$final_dir/login.keyring" ]; then
            echo "keyring-migrate: $final_dir/login.keyring already exists, nothing to do."
            exit 0
          fi
          if ! { : </dev/tty; } 2>/dev/null; then
            echo "keyring-migrate: needs a terminal to ask for your login password; run keyring-migrate from one." >&2
            exit 1
          fi

          chkpwd=""
          for candidate in /run/wrappers/bin/unix_chkpwd /usr/sbin/unix_chkpwd /sbin/unix_chkpwd; do
            if [ -x "$candidate" ]; then
              chkpwd="$candidate"
              break
            fi
          done
          if [ -z "$chkpwd" ]; then
            echo "keyring-migrate: no unix_chkpwd to verify the login password with." >&2
            exit 1
          fi

          ask() {
            local reply
            IFS= read -rs -p "$1: " reply </dev/tty
            printf '\n' >/dev/tty
            REPLY="$reply"
          }

          login_password=""
          for _ in 1 2 3; do
            ask "Login password for $user, to open the new lys-secrets keyring"
            if printf '%s\0' "$REPLY" | "$chkpwd" "$user" nullok; then
              login_password="$REPLY"
              break
            fi
            echo "keyring-migrate: that is not the login password." >&2
          done
          if [ -z "$login_password" ]; then
            echo "keyring-migrate: no valid login password; nothing was changed." >&2
            exit 1
          fi

          work=$(mktemp -d "$data/.keyring-migrate.XXXXXX")
          runtime=$(mktemp -d)
          pids=()
          source_pid=""
          stop_processes() {
            local all=("''${pids[@]}")
            if [ -n "$source_pid" ]; then
              all+=("$source_pid")
            fi
            if [ "''${#all[@]}" -gt 0 ]; then
              kill "''${all[@]}" 2>/dev/null || :
              wait "''${all[@]}" 2>/dev/null || :
            fi
            pids=()
            source_pid=""
          }
          cleanup() {
            stop_processes
            rm -rf "$work" "$runtime"
          }
          trap cleanup EXIT
          mkdir -p "$work/empty" "$work/data" "$work/state" "$runtime/source" "$runtime/target"

          start_bus() {
            XDG_DATA_HOME="$work/empty" XDG_DATA_DIRS="$work/empty" \
              dbus-daemon --config-file=${pkgs.dbus}/share/dbus-1/session.conf --nofork --nopidfile --address="unix:path=$1" &
            pids+=("$!")
            for _ in $(seq 100); do
              if [ -S "$1" ]; then
                return 0
              fi
              sleep 0.05
            done
            echo "keyring-migrate: the private bus at $1 never came up." >&2
            exit 1
          }

          start_source() {
            printf '%s' "$1" | DBUS_SESSION_BUS_ADDRESS="$source_bus" XDG_RUNTIME_DIR="$runtime/source" \
              XDG_DATA_HOME="$data" gnome-keyring-daemon --foreground --components=secrets --unlock >>"$work/source.log" 2>&1 &
            source_pid="$!"
          }

          source_bus="unix:path=$runtime/source.sock"
          target_bus="unix:path=$runtime/target.sock"
          start_bus "$runtime/source.sock"
          start_bus "$runtime/target.sock"

          DBUS_SESSION_BUS_ADDRESS="$target_bus" XDG_RUNTIME_DIR="$runtime/target" \
            XDG_DATA_HOME="$work/data" XDG_STATE_HOME="$work/state" \
            lys-secrets --unlock-fd 3 3<<<"$login_password" >"$work/target.log" 2>&1 &
          pids+=("$!")

          copy() {
            status=0
            copy-keyring-secrets "$source_bus" "$target_bus" || status=$?
          }

          start_source "$login_password"
          copy
          attempts=0
          while [ "$status" -eq 3 ] && [ "$attempts" -lt 3 ]; do
            kill "$source_pid"
            wait "$source_pid" 2>/dev/null || :
            attempts=$((attempts + 1))
            ask "The old keyring has a different password; old keyring password"
            start_source "$REPLY"
            copy
          done
          if [ "$status" -ne 0 ]; then
            cat "$work/source.log" "$work/target.log" >&2
            echo "keyring-migrate: copying failed with status $status; nothing was changed." >&2
            exit "$status"
          fi

          stop_processes

          staged="$work/data/lys-secrets"
          if [ ! -f "$staged/login.keyring" ]; then
            echo "keyring-migrate: lys-secrets wrote no login collection; nothing was changed." >&2
            exit 1
          fi
          mkdir -p "$final_dir"
          chmod 0700 "$final_dir"
          for file in "$staged"/*; do
            if [ "$file" != "$staged/login.keyring" ]; then
              mv "$file" "$final_dir/"
            fi
          done
          mv "$staged/login.keyring" "$final_dir/login.keyring"
          echo "keyring-migrate: secrets are in $final_dir; the old keyring at $source_keyring was left untouched."
        '';
      };
    in
    {
      imports = [ inputs.lys-secrets.homeManagerModules.default ];

      services.lys-secrets = lib.mkIf (config.features.desktop && config.host.platform == "linux") {
        enable = true;
        package = pkgs.lys-secrets;
      };

      home.packages = lib.mkIf config.features.desktop [
        pkgs.gnupg
        keyringMigrate
      ];

      stubbe.setup = {
        lysSecrets = lib.mkIf config.features.desktop {
          privileged = true;
          title = "Moving to lys-secrets (in place of gnome-keyring)";
          body = ''
            Copy every secret from the gnome-keyring login keyring into lys-secrets
            and verify each one, so Chrome, Slack and the rest keep working. This
            asks for your login password. The old keyring file is left untouched.

            Then stop gnome-keyring from claiming org.freedesktop.secrets at the
            next login: mask its user units and remove the PAM lines this repo
            added. It keeps running until you log out.
          '';
          script = ''
            ${lib.getExe keyringMigrate}

            unit_dir="${config.xdg.configHome}/systemd/user"
            mkdir -p "$unit_dir"
            ln -sfT /dev/null "$unit_dir/gnome-keyring-daemon.service"
            ln -sfT /dev/null "$unit_dir/gnome-keyring-daemon.socket"

            for file in ${lib.escapeShellArgs pamFiles}; do
              if [ -f "$file" ]; then
                sudo sed -i \
                  -e '/^auth optional pam_gnome_keyring\.so$/d' \
                  -e '/^session optional pam_gnome_keyring\.so auto_start$/d' \
                  -e '/^password optional pam_gnome_keyring\.so use_authtok$/d' \
                  "$file"
              fi
            done
          '';
        };

        # Nix's PAM modules expect /run/wrappers/bin/unix_chkpwd, which only
        # NixOS provides. Without it, lys-shell's session-lock unlock cannot verify
        # the password at all.
        pamWrappers = lib.mkIf config.features.lysWm {
          privileged = true;
          title = "⚠️  Nix PAM wrapper setup required for lys-shell lock authentication";
          body = ''
            This will install a systemd service to enable password authentication
            for lys-shell's session lock. The service will persist across reboots.
          '';
          script = ''
            ${pkgs.stubbe.setup.text {
              name = "nix-pam-wrappers.service";
              target = "/etc/systemd/system/nix-pam-wrappers.service";
              text = pkgs.stubbe.gen.unitText {
                Unit = {
                  Description = "Setup Nix PAM wrappers for non-NixOS systems";
                  DefaultDependencies = "no";
                  Before = "sysinit.target";
                  ConditionPathExists = "!/run/wrappers/bin/unix_chkpwd";
                };
                Service = {
                  Type = "oneshot";
                  RemainAfterExit = "yes";
                  ExecStart = [
                    "/usr/bin/mkdir -p /run/wrappers/bin"
                    "/usr/bin/ln -sf /usr/sbin/unix_chkpwd /run/wrappers/bin/unix_chkpwd"
                  ];
                };
                Install.WantedBy = "sysinit.target";
              };
            }}
            ${pkgs.stubbe.setup.reloadUnits}
            sudo systemctl enable --now nix-pam-wrappers.service
          '';
        };
      };
    };
}
