_: {
  perSystem =
    { pkgs, ... }:
    let
      keyringMigrate = pkgs.stubbe.keyringMigrate {
        chkpwdCandidates = [ "${pkgs.writeShellScript "accept-any-password" "exit 0"}" ];
      };

      keyringClient =
        pkgs.writers.writePython3Bin "keyring-client"
          {
            libraries = with pkgs.python3Packages; [
              secretstorage
              jeepney
            ];
          }
          ''
            import sys

            from jeepney.io.blocking import open_dbus_connection
            from secretstorage.collection import Collection

            LOGIN = "/org/freedesktop/secrets/collection/login"
            SCHEMA = "org.freedesktop.Secret.Generic"


            def put(login, name, value):
                login.create_item(
                    name,
                    {"app": name, "xdg:schema": SCHEMA},
                    value.encode(),
                    replace=True,
                )


            def dump(login):
                items = login.get_all_items()
                lines = [f"{i.get_label()}={i.get_secret().decode()}" for i in items]
                print(" ".join(sorted(lines)))


            def main(command, *args):
                login = Collection(open_dbus_connection(bus="SESSION"), LOGIN)
                if command == "put":
                    put(login, *args)
                else:
                    dump(login)


            main(*sys.argv[1:])
          '';
    in
    {
      checks.keyring-migrate = pkgs.stubbe.check {
        name = "keyring-migrate";
        timeout = 300;
        nativeBuildInputs = [
          keyringClient
          keyringMigrate
          pkgs.dbus
          pkgs.gnome-keyring
          pkgs.lys-secrets
          pkgs.util-linux
        ];
        text = ''
          password=login-password
          printf '%s' "$password" >password
          pids=()
          trap 'kill "''${pids[@]}" 2>/dev/null || :' EXIT

          start_bus() {
            dbus-daemon --config-file=${pkgs.dbus}/share/dbus-1/session.conf --nofork --nopidfile --address="unix:path=$1" &
            pids+=("$!")
            for _ in $(seq 100); do
              if [ -S "$1" ]; then
                return 0
              fi
              sleep 0.05
            done
            echo "the bus at $1 never came up" >&2
            exit 1
          }

          new_home() {
            root=$(mktemp -d "$PWD/h.XXXX")
            export HOME="$root/home" XDG_RUNTIME_DIR="$root/run"
            export XDG_DATA_HOME="$HOME/share" XDG_STATE_HOME="$HOME/state"
            mkdir -p "$XDG_DATA_HOME" "$XDG_STATE_HOME"
            mkdir -m 700 "$XDG_RUNTIME_DIR"
            start_bus "$root/bus"
            export DBUS_SESSION_BUS_ADDRESS="unix:path=$root/bus"
            seed_gnome_keyring
          }

          seed_gnome_keyring() {
            local seed_bus="$root/seed-bus" keyring_pid
            start_bus "$seed_bus"
            (
              export DBUS_SESSION_BUS_ADDRESS="unix:path=$seed_bus"
              gnome-keyring-daemon --foreground --components=secrets --unlock <password >/dev/null 2>&1 &
              keyring_pid=$!
              for _ in $(seq 100); do
                if keyring-client put chrome chrome-old 2>/dev/null; then
                  break
                fi
                sleep 0.1
              done
              keyring-client put shared shared-old
              kill "$keyring_pid"
              wait "$keyring_pid" 2>/dev/null || :
            )
            test -f "$XDG_DATA_HOME/keyrings/login.keyring"
          }

          start_daemon() {
            lys-secrets "$@" >"$root/daemon.log" 2>&1 &
            daemon_pid=$!
            pids+=("$daemon_pid")
            for _ in $(seq 300); do
              if [ -S "$XDG_RUNTIME_DIR/lys-secrets/control" ]; then
                return 0
              fi
              sleep 0.1
            done
            cat "$root/daemon.log" >&2
            echo "lys-secrets never served its control socket" >&2
            exit 1
          }

          start_daemon_unlocked() {
            start_daemon --unlock-fd 3 3<"$1"
            for _ in $(seq 300); do
              if keyring-client dump >/dev/null 2>&1; then
                return 0
              fi
              sleep 0.1
            done
            echo "lys-secrets never unlocked the login collection" >&2
            exit 1
          }

          stop_daemon() {
            kill "$daemon_pid"
            wait "$daemon_pid" 2>/dev/null || :
          }

          migrate() {
            printf '%s\n' "$password" | script -qec keyring-migrate /dev/null | tr -d '\r'
          }

          expect_items() {
            local got
            got=$(keyring-client dump)
            if [ "$got" != "$1" ]; then
              echo "expected items '$1', got '$got'" >&2
              exit 1
            fi
          }

          expect_output() {
            if ! grep -qF -- "$2" <<<"$1"; then
              printf 'expected %s in:\n%s\n' "$2" "$1" >&2
              exit 1
            fi
          }

          marker() { printf '%s' "$XDG_STATE_HOME/lys-secrets/gnome-keyring-migrated"; }

          new_home
          start_daemon_unlocked password
          test -f "$XDG_DATA_HOME/lys-secrets/login.keyring"
          keyring-client put shared shared-newer
          expect_output "$(migrate)" "1 secrets copied and verified, 0 already there"
          expect_items "chrome=chrome-old shared=shared-newer"
          test -e "$(marker)"
          expect_output "$(script -qec keyring-migrate /dev/null </dev/null)" "already migrated"
          stop_daemon
          start_daemon_unlocked password
          expect_items "chrome=chrome-old shared=shared-newer"
          rm "$(marker)"
          expect_output "$(migrate)" "kept, lys-secrets already holds another value: shared"
          expect_items "chrome=chrome-old shared=shared-newer"
          stop_daemon

          new_home
          start_daemon_unlocked password
          stop_daemon
          start_daemon
          migrate >/dev/null
          expect_items "chrome=chrome-old shared=shared-old"
          stop_daemon

          new_home
          start_daemon_unlocked password
          stop_daemon
          migrate >/dev/null
          start_daemon_unlocked password
          expect_items "chrome=chrome-old shared=shared-old"
          stop_daemon

          new_home
          migrate >/dev/null
          start_daemon_unlocked password
          expect_items "chrome=chrome-old shared=shared-old"
          stop_daemon

          new_home
          printf other-password >other-password
          start_daemon_unlocked other-password
          stop_daemon
          start_daemon
          if migrate >"$root/out"; then
            echo "a login password that does not open the collection must fail" >&2
            exit 1
          fi
          expect_output "$(cat "$root/out")" "does not open the lys-secrets login collection"
          test ! -e "$(marker)"
          stop_daemon

          touch "$out"
        '';
      };
    };
}
