_: {
  flake.modules.homeManager.packagesHm =
    {
      pkgs,
      config,
      ...
    }:
    let
      flakeDir = "${config.home.homeDirectory}/.stubbe";
    in
    {
      home.packages = [
        (pkgs.writeShellScriptBin "hm" ''
          set -euo pipefail

          hm_flake_dir="''${HM_FLAKE_DIR:-${flakeDir}}"

          has_cmd() {
            command -v "$1" >/dev/null 2>&1
          }

          if has_cmd readlink; then
            hm_flake_dir=$(readlink -f "$hm_flake_dir" 2>/dev/null || echo "$hm_flake_dir")
          fi

          hm_flake_ref="path:$hm_flake_dir"

          ensure_sudo() {
            if [[ "''${1:-}" == "true" ]]; then
              echo "Requesting sudo..."
              sudo -v
            fi
          }

          update_system() {
            local needs_sudo="false"

            if has_cmd pacman || has_cmd apt || has_cmd dnf || has_cmd snap; then
              needs_sudo="true"
            fi

            ensure_sudo "$needs_sudo"

            if has_cmd pacman; then
              echo "Updating pacman packages"
              sudo pacman -Syu --noconfirm
            fi

            if has_cmd apt; then
              echo "Updating apt packages"
              sudo apt update
              sudo apt upgrade -y
              sudo apt autoremove -y
            fi

            if has_cmd dnf; then
              echo "Updating dnf packages"
              sudo dnf upgrade -y
            fi

            if has_cmd snap; then
              echo "Updating snap packages"
              sudo snap refresh
            fi

            if has_cmd flatpak; then
              echo "Updating flatpak packages"
              flatpak update -y
              flatpak uninstall --unused -y
            fi

            if has_cmd nix; then
              echo "Updating nix inputs"
              nix flake update --flake "$hm_flake_ref"
            fi

            if has_cmd nix-channel; then
              nix-channel --update
            fi
          }

          usage() {
            cat <<'EOF'
          Usage: hm <command> [args]

          Commands:
            update              Update system package managers and nix inputs
            upgrade             Update system packages and apply home-manager switch
            whoami              Print "<hostname> <age-pubkey>" for this machine
            trust [name] <key>  Add an age recipient to .sops.yaml and re-wrap secrets/*
                                  - hm trust <name> <pubkey>
                                  - hm trust <pubkey>           (auto-named)
                                  - cmd | hm trust              (e.g. ssh other hm whoami | hm trust)
            secret edit <name>  Open secrets/<name>.yaml in $EDITOR via sops (creates if absent)
            secret rotate <name>  Re-roll the data key for secrets/<name>.yaml
            help                Show this help message

          Other args are passed through to home-manager.
          EOF
          }

          hm_whoami() {
            if [ ! -f "$HOME/.ssh/id_ed25519.pub" ]; then
              echo "hm whoami: ~/.ssh/id_ed25519.pub not found" >&2
              return 1
            fi
            local pubkey host
            pubkey=$(${pkgs.ssh-to-age}/bin/ssh-to-age < "$HOME/.ssh/id_ed25519.pub")
            host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")
            printf '%s %s\n' "$host" "$pubkey"
          }

          hm_trust() {
            local name="" pubkey=""

            # Resolve (name, pubkey) from one of three forms:
            #   1) hm trust <name> <pubkey>            — explicit
            #   2) hm trust <pubkey>                   — auto-name
            #   3) cmd | hm trust                      — stdin "<name> <pubkey>" or "<pubkey>"
            if [ "$#" -ge 2 ]; then
              name="$1"; pubkey="$2"
            elif [ "$#" -eq 1 ]; then
              pubkey="$1"
            elif [ "$#" -eq 0 ] && [ ! -t 0 ]; then
              local line
              if ! IFS= read -r line || [ -z "$line" ]; then
                echo "hm trust: empty stdin (expected '<name> <pubkey>' or '<pubkey>')" >&2
                return 2
              fi
              # shellcheck disable=SC2086
              set -- $line
              if [ "$#" -ge 2 ]; then
                name="$1"; pubkey="$2"
              else
                pubkey="$1"
              fi
            else
              cat <<EOF >&2
          Usage:
            hm trust <name> <pubkey>      # explicit
            hm trust <pubkey>             # auto-name from hostname or pubkey suffix
            <cmd> | hm trust              # e.g. ssh laptop2 hm whoami | hm trust
          EOF
              return 2
            fi

            # Auto-derive name if not supplied. Prefer the local hostname when
            # the pubkey is *this machine's* SSH-derived recipient; otherwise
            # fall back to the pubkey's last 8 chars so the line is at least
            # eyeball-distinguishable.
            if [ -z "$name" ]; then
              local local_pubkey=""
              if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
                local_pubkey=$(${pkgs.ssh-to-age}/bin/ssh-to-age < "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || true)
              fi
              if [ -n "$local_pubkey" ] && [ "$pubkey" = "$local_pubkey" ]; then
                name=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")
              else
                name="''${pubkey: -8}"
              fi
            fi

            if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
              echo "hm trust: derived name '$name' must match [A-Za-z0-9_-]+" >&2
              return 2
            fi

            # Validate the bech32-encoded age pubkey by attempting an
            # encryption with it. age fails fast on a bad checksum, so we
            # don't mutate .sops.yaml on bad input.
            if ! ${pkgs.age}/bin/age -r "$pubkey" -o /dev/null </dev/null 2>/dev/null; then
              echo "hm trust: '$pubkey' is not a valid age recipient pubkey" >&2
              return 2
            fi

            local sops_yaml="$hm_flake_dir/.sops.yaml"
            if [ ! -f "$sops_yaml" ]; then
              echo "hm trust: $sops_yaml not found" >&2
              return 1
            fi

            if grep -qF "$pubkey" "$sops_yaml"; then
              echo "hm trust: $pubkey already present in .sops.yaml — nothing to do."
              return 0
            fi

            # Snapshot for rollback if any sops updatekeys call fails.
            local backup
            backup=$(mktemp)
            cp "$sops_yaml" "$backup"

            rollback() {
              cp "$backup" "$sops_yaml"
              rm -f "$backup"
              echo "hm trust: rolled back .sops.yaml" >&2
            }

            # Append the new recipient line directly after the last existing
            # 'age1...' entry under the age list. Awk preserves comments and
            # surrounding structure, unlike a YAML round-trip.
            local tmp
            tmp=$(mktemp)
            awk -v new="          - $pubkey  # $name" '
              /^          - age1/ { last = NR }
              { lines[NR] = $0 }
              END {
                for (i = 1; i <= NR; i++) {
                  print lines[i]
                  if (i == last) print new
                }
              }
            ' "$sops_yaml" > "$tmp"
            mv "$tmp" "$sops_yaml"

            echo "Added $name → $pubkey to .sops.yaml"

            # Re-wrap each existing secrets file's data key for the new recipient.
            # Any failure rolls .sops.yaml back so the repo isn't left half-edited.
            shopt -s nullglob
            local secret count=0
            for secret in "$hm_flake_dir"/secrets/*.yaml; do
              echo "Re-wrapping $(basename "$secret")"
              if ! ${pkgs.sops}/bin/sops updatekeys --yes "$secret"; then
                rollback
                return 1
              fi
              count=$((count + 1))
            done
            rm -f "$backup"

            cat <<MSG

          Trusted $name across $count secret file(s).
          Review:  git -C "$hm_flake_dir" diff -- .sops.yaml secrets/
          Commit:  git -C "$hm_flake_dir" add .sops.yaml secrets/ && \\
                   git -C "$hm_flake_dir" commit -m "trust: add $name age recipient"
          MSG
          }

          hm_secret() {
            local action="''${1:-}"
            local name="''${2:-}"
            if [ -z "$action" ] || [ -z "$name" ]; then
              echo "Usage: hm secret {edit|rotate} <name>" >&2
              return 2
            fi
            # Accept either "intelephense" or "intelephense.yaml"; canonicalise to the .yaml form.
            local file="''${name%.yaml}.yaml"
            local path="$hm_flake_dir/secrets/$file"
            case "$action" in
              edit)
                # sops handles both create and edit transparently — no exists-check.
                ${pkgs.sops}/bin/sops "$path"
                ;;
              rotate)
                if [ ! -f "$path" ]; then
                  echo "hm secret rotate: $path does not exist" >&2
                  return 1
                fi
                ${pkgs.sops}/bin/sops --rotate -i "$path"
                echo "Re-rolled data key for $file. Recipients unchanged."
                ;;
              *)
                echo "hm secret: unknown action '$action' (want edit|rotate)" >&2
                return 2
                ;;
            esac
          }

          case "''${1:-}" in
            update)
              shift
              update_system
              ;;
            upgrade)
              shift
              update_system
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              home-manager switch --flake "$hm_flake_ref" --impure "$@"
              home-manager expire-generations "-7 days" >/dev/null 2>&1
              nix-store --gc --quiet >/dev/null 2>&1 &!
              ;;
            whoami)
              shift
              hm_whoami
              ;;
            trust)
              shift
              hm_trust "$@"
              ;;
            secret)
              shift
              hm_secret "$@"
              ;;
            help|-h|--help)
              usage
              ;;
            switch|build|news|instantiate)
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              subcmd="$1"
              shift
              home-manager "$subcmd" --flake "$hm_flake_ref" --impure "$@"
              home-manager expire-generations "-7 days" >/dev/null 2>&1 &!
              ;;
            *)
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              home-manager --impure "$@"
              home-manager expire-generations "-7 days" >/dev/null 2>&1 &!
              ;;
          esac
        '')
        (pkgs.writeShellScriptBin "nixos-iso" ''
          set -euo pipefail

          flake_dir="''${NIXOS_FLAKE_DIR:-${flakeDir}}"
          out_link="''${NIXOS_ISO_OUT_LINK:-$PWD/result-nixos-installer-iso}"

          has_cmd() {
            command -v "$1" >/dev/null 2>&1
          }

          if has_cmd readlink; then
            flake_dir=$(readlink -f "$flake_dir" 2>/dev/null || echo "$flake_dir")
          fi

          flake_ref="path:$flake_dir"

          usage() {
            cat <<'EOF'
          Usage: nixos-iso <command> [args]

          Commands:
            build [args]          Build the installer ISO with --impure
            path [args]           Build the ISO and print the output path
            devices               List removable/block devices
            burn <device> --yes   Build the ISO and write it to a USB device
            help                  Show this help message

          Environment:
            NIXOS_FLAKE_DIR       Override the flake directory (default: ~/.stubbe)
            NIXOS_ISO_OUT_LINK    Override the build result link

          The ISO build always reads ~/.ssh impurely and embeds detected public
          and private SSH key files into /root/.ssh on the live image.
          EOF
          }

          build_iso() {
            nix build --impure "$flake_ref#installer-iso" --out-link "$out_link" "$@"
          }

          print_iso_path() {
            build_iso "$@" >/dev/null
            readlink -f "$out_link"
          }

          list_devices() {
            lsblk -d -o NAME,SIZE,MODEL,TRAN,RM,TYPE,MOUNTPOINTS
          }

          burn_iso() {
            local device=""
            local yes="false"
            local nix_args=()

            while [[ "$#" -gt 0 ]]; do
              case "$1" in
                --yes|-y)
                  yes="true"
                  shift
                  ;;
                --)
                  shift
                  nix_args+=("$@")
                  break
                  ;;
                -* )
                  nix_args+=("$1")
                  shift
                  ;;
                *)
                  if [[ -z "$device" ]]; then
                    device="$1"
                  else
                    nix_args+=("$1")
                  fi
                  shift
                  ;;
              esac
            done

            if [[ -z "$device" ]]; then
              usage >&2
              exit 2
            fi

            if [[ ! -b "$device" ]]; then
              echo "Not a block device: $device" >&2
              exit 1
            fi

            case "$device" in
              /dev/sd*|/dev/nvme*n*|/dev/mmcblk*)
                ;;
              *)
                echo "Refusing unexpected device path: $device" >&2
                exit 1
                ;;
            esac

            if [[ "$yes" != "true" ]]; then
              echo "Refusing to write without --yes because this destroys data on $device" >&2
              exit 2
            fi

            if [[ -n "$(lsblk -nr -o MOUNTPOINTS "$device" | tr -d '[:space:]')" ]]; then
              echo "Refusing to write because $device or one of its partitions is mounted" >&2
              exit 1
            fi

            build_iso "''${nix_args[@]}"
            iso_path=$(readlink -f "$out_link")

            echo "Writing $iso_path to $device"
            sudo dd if="$iso_path" of="$device" bs=4M status=progress oflag=sync conv=fsync
            sync
          }

          case "''${1:-}" in
            build)
              shift
              build_iso "$@"
              ;;
            path)
              shift
              print_iso_path "$@"
              ;;
            devices)
              shift
              list_devices
              ;;
            burn|write)
              shift
              burn_iso "$@"
              ;;
            help|-h|--help|"")
              usage
              ;;
            *)
              build_iso "$@"
              ;;
          esac
        '')
      ];
    };
}
