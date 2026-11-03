# Branch of the pkgs.stubbe helper tree (see ./default.nix).
_: {
  stubbe.pkgsLib.keyringMigrate =
    {
      final,
      lib,
      stubbe,
      ...
    }:
    {
      chkpwdCandidates ? [
        "/run/wrappers/bin/unix_chkpwd"
        "/usr/sbin/unix_chkpwd"
        "/sbin/unix_chkpwd"
      ],
    }:
    let
      copyKeyringSecrets =
        final.writers.writePython3Bin "copy-keyring-secrets"
          {
            libraries = with final.python3Packages; [
              secretstorage
              jeepney
            ];
          }
          ''
            import hashlib
            import socket
            import struct
            import sys
            import time

            import secretstorage
            from jeepney import DBusAddress, new_method_call
            from jeepney.io.blocking import open_dbus_connection
            from jeepney.wrappers import DBusErrorResponse
            from secretstorage.collection import Collection
            from secretstorage.exceptions import ItemNotFoundException

            SERVICE = "org.freedesktop.secrets"
            COLLECTIONS = "/org/freedesktop/secrets/collection/"
            SOURCE_LOCKED = 3
            CONTROL_OK = b"\x00"
            CONTROL_WRONG_PASSWORD = b"\x01"
            CONTROL_TIMEOUT_SECONDS = 30


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


            def wait_for_source_login(connection):
                for _ in range(100):
                    try:
                        return Collection(connection, COLLECTIONS + "login")
                    except (DBusErrorResponse, ItemNotFoundException):
                        time.sleep(0.1)
                sys.exit("gnome-keyring never loaded its login collection")


            def ask_control(path, request):
                with socket.socket(socket.AF_UNIX) as control:
                    control.settimeout(CONTROL_TIMEOUT_SECONDS)
                    control.connect(path)
                    control.sendall(request)
                    return control.recv(1)


            def unlock_login(path, password):
                request = struct.pack(">I", len(password)) + password
                for _ in range(100):
                    try:
                        status = ask_control(path, request)
                        break
                    except (FileNotFoundError, ConnectionRefusedError):
                        time.sleep(0.1)
                else:
                    sys.exit(f"no lys-secrets answers on {path}")
                if status == CONTROL_WRONG_PASSWORD:
                    sys.exit(
                        "the login password does not open the lys-secrets "
                        "login collection"
                    )
                if status != CONTROL_OK:
                    sys.exit(f"lys-secrets on {path} answered {status!r}")


            def holding_same_attributes(collection, attributes):
                for item in collection.search_items(attributes):
                    if item.get_attributes() == attributes:
                        return item
                return None


            def digest(item):
                return hashlib.sha256(item.get_secret()).hexdigest()


            def main(source_address, target_address, control_path):
                source = open_dbus_connection(bus=source_address)
                target = open_dbus_connection(bus=target_address)
                wait_for_service(source)
                wait_for_source_login(source)
                unlock_login(control_path, sys.stdin.buffer.read())

                login = Collection(target, COLLECTIONS + "login")
                copied = 0
                present = 0
                different = []
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
                        label = item.get_label()
                        attributes = item.get_attributes()
                        held = holding_same_attributes(login, attributes)
                        if held is not None:
                            if digest(held) == digest(item):
                                present += 1
                            else:
                                different.append(label)
                            continue
                        created = login.create_item(
                            label,
                            attributes,
                            item.get_secret(),
                            content_type=item.get_secret_content_type(),
                        )
                        if digest(created) != digest(item):
                            sys.exit(f"copy of {label!r} does not match")
                        print(f"  copied: {label}")
                        copied += 1

                print(
                    f"keyring-migrate: {copied} secrets copied and verified, "
                    f"{present} already there"
                )
                if different:
                    names = ", ".join(different)
                    print(
                        "keyring-migrate: kept, lys-secrets already holds "
                        f"another value: {names}"
                    )
                if skipped:
                    names = ", ".join(skipped)
                    print(f"keyring-migrate: NOT copied, still locked: {names}")


            main(sys.argv[1], sys.argv[2], sys.argv[3])
          '';
    in
    stubbe.bashApp {

      name = "keyring-migrate";
      runtimeInputs = with final; [
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
        state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/lys-secrets"
        migrated_marker="$state_dir/gnome-keyring-migrated"

        if [ ! -f "$source_keyring" ]; then
          echo "keyring-migrate: no gnome-keyring login keyring at $source_keyring, nothing to copy."
          exit 0
        fi
        if [ -e "$migrated_marker" ]; then
          echo "keyring-migrate: already migrated ($migrated_marker exists), nothing to do."
          exit 0
        fi
        if ! { : </dev/tty; } 2>/dev/null; then
          echo "keyring-migrate: needs a terminal to ask for your login password; run keyring-migrate from one." >&2
          exit 1
        fi

        chkpwd=""
        chkpwd_candidates=(${lib.escapeShellArgs chkpwdCandidates})
        for candidate in "''${chkpwd_candidates[@]}"; do
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
          ask "Login password for $user, to open the lys-secrets keyring"
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

        work=$(mktemp -d)
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
        mkdir -p "$work/empty" "$work/state" "$runtime/source" "$runtime/target"
        touch "$work/source.log" "$work/target.log"

        start_bus() {
          XDG_DATA_HOME="$work/empty" XDG_DATA_DIRS="$work/empty" \
            dbus-daemon --config-file=${final.dbus}/share/dbus-1/session.conf --nofork --nopidfile --address="unix:path=$1" &
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
        start_bus "$runtime/source.sock"

        live_control="''${XDG_RUNTIME_DIR:?keyring-migrate: XDG_RUNTIME_DIR is not set}/lys-secrets/control"
        if [ -S "$live_control" ]; then
          target_bus="''${DBUS_SESSION_BUS_ADDRESS:?keyring-migrate: DBUS_SESSION_BUS_ADDRESS is not set}"
          target_control="$live_control"
        else
          target_bus="unix:path=$runtime/target.sock"
          target_control="$runtime/target/lys-secrets/control"
          start_bus "$runtime/target.sock"
          DBUS_SESSION_BUS_ADDRESS="$target_bus" XDG_RUNTIME_DIR="$runtime/target" \
            XDG_DATA_HOME="$data" XDG_STATE_HOME="$work/state" \
            lys-secrets >"$work/target.log" 2>&1 &
          pids+=("$!")
        fi

        copy() {
          status=0
          printf '%s' "$login_password" |
            copy-keyring-secrets "$source_bus" "$target_bus" "$target_control" || status=$?
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
          echo "keyring-migrate: copying failed with status $status; run keyring-migrate again, it keeps what already arrived." >&2
          exit "$status"
        fi

        stop_processes

        mkdir -p "$state_dir"
        touch "$migrated_marker"
        echo "keyring-migrate: secrets are in $data/lys-secrets; the old keyring at $source_keyring was left untouched."
      '';
    };
}
