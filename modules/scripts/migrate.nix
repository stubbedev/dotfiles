_: {
  flake.modules.homeManager.script-migrate =
    { lib, pkgs, ... }:
    let
      carried = [
        "git"
        ".ssh"
        ".gnupg"
      ];

      migrate = pkgs.stubbe.bashApp {
        name = "stb-migrate";
        runtimeInputs = with pkgs; [
          coreutils
          findutils
          gnused
          inetutils
          rsync
        ];
        text = ''
          carried=(${lib.escapeShellArgs carried})

          usage() {
            cat <<'EOF'
          Usage:
            stb-migrate backup [--skip-unreadable] <dest>
            stb-migrate restore [--from <host>] <dest>

          <dest> is a directory, local (a mounted drive) or remote over ssh
          ([user@]host:dir, e.g. desktop.local:migrate). Each machine gets its own
          <dest>/<hostname>/ with the mirrored files under home/ and a manifest.

          backup   Mirror ~/git, ~/.ssh and ~/.gnupg into <dest>/<hostname>/home,
                   everything included, compressed in transit when remote. Run it
                   again any time: only changes are sent, and files deleted here
                   are deleted there. Stops if any carried file is unreadable;
                   --skip-unreadable leaves those out and lists them in the
                   manifest instead.
          restore  Copy <dest>/<hostname>/home back into ~ with permissions kept.
                   Files that already exist are left untouched. --from restores
                   another machine's mirror.
          EOF
          }

          die() {
            echo "stb-migrate: $*" >&2
            exit 1
          }

          is_remote() {
            [[ "$1" =~ ^[^/]*: ]]
          }

          rsync_into() {
            local status=0
            rsync --archive --hard-links --partial --mkpath --human-readable --info=progress2 "$@" || status=$?
            case "$status" in
              0) ;;
              24) echo "stb-migrate: some files vanished while copying (deleted mid-run); run it again to settle" >&2 ;;
              *) die "rsync failed with exit status $status" ;;
            esac
          }

          list_unreadable() {
            local root=$1
            find "$HOME/$root" -xdev ! -readable -prune -printf "$root/%P\n"
          }

          backup() {
            local skip_unreadable=false dest=""
            while [ "$#" -gt 0 ]; do
              case "$1" in
                --skip-unreadable) skip_unreadable=true ;;
                -*) die "unknown backup option: $1" ;;
                *)
                  [ -z "$dest" ] || die "backup takes one destination, got '$dest' and '$1'"
                  dest=$1
                  ;;
              esac
              shift
            done
            [ -n "$dest" ] || { usage >&2; exit 2; }

            local -a transport=()
            if is_remote "$dest"; then
              transport=(--compress --compress-choice=zstd)
            else
              [ -d "$dest" ] || die "destination '$dest' is not a directory (mount the drive first)"
              case "$(stat -f -c %T "$dest")" in
                msdos | vfat | exfat) die "$dest cannot hold Unix permissions or symlinks; use an ext4 or btrfs drive, or a remote host:dir" ;;
              esac
            fi

            local -a roots=()
            local root
            for root in "''${carried[@]}"; do
              if [ -e "$HOME/$root" ]; then
                roots+=("$root")
              else
                echo "stb-migrate: ~/$root does not exist; nothing to carry there"
              fi
            done
            [ "''${#roots[@]}" -gt 0 ] || die "none of ~/{''${carried[*]}} exist"

            work=$(mktemp -d)
            trap 'rm -rf "$work"' EXIT

            echo "==> Checking that every carried file is readable"
            for root in "''${roots[@]}"; do
              list_unreadable "$root"
            done >"$work/unreadable"
            if [ -s "$work/unreadable" ]; then
              if [ "$skip_unreadable" != true ]; then
                sed 's|^|  ~/|' "$work/unreadable" >&2
                die "the $(wc -l <"$work/unreadable") paths above are not readable by $USER; fix their ownership or permissions, or pass --skip-unreadable to leave them out"
              fi
              echo "    leaving out $(wc -l <"$work/unreadable") unreadable paths (listed in the manifest)"
            fi

            sed 's|.*|/&|' "$work/unreadable" >"$work/filter"

            {
              echo "host: $(hostname -s)"
              echo "taken: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
              echo "carried: ''${roots[*]}"
              echo "excluded unreadable:"
              sed 's|^|  ~/|' "$work/unreadable"
            } >"$work/manifest"

            local target
            target="''${dest%/}/$(hostname -s)"
            echo "==> Mirroring into $target/home"
            rsync_into "''${transport[@]}" --relative --delete --delete-excluded \
              --exclude-from="$work/filter" "''${roots[@]/#/$HOME/./}" "$target/home/"
            rsync_into "$work/manifest" "$target/manifest"

            echo "Done: $target"
            echo "Restore on the new system with: stb-migrate restore $dest"
          }

          restore() {
            local from="" dest=""
            while [ "$#" -gt 0 ]; do
              case "$1" in
                --from)
                  from=''${2:?--from requires a host name}
                  shift
                  ;;
                -*) die "unknown restore option: $1" ;;
                *)
                  [ -z "$dest" ] || die "restore takes one source, got '$dest' and '$1'"
                  dest=$1
                  ;;
              esac
              shift
            done
            [ -n "$dest" ] || { usage >&2; exit 2; }

            local -a transport=()
            if is_remote "$dest"; then
              transport=(--compress --compress-choice=zstd)
            fi

            local source
            source="''${dest%/}/''${from:-$(hostname -s)}"
            echo "==> Restoring $source/home into $HOME (existing files are kept)"
            rsync_into "''${transport[@]}" --ignore-existing "$source/home/" "$HOME/"
            echo "Done."
          }

          case "''${1:-}" in
            backup)
              shift
              backup "$@"
              ;;
            restore)
              shift
              restore "$@"
              ;;
            -h | --help)
              usage
              ;;
            *)
              usage >&2
              exit 2
              ;;
          esac
        '';
      };
    in
    {
      home.packages = [ migrate ];
    };
}
