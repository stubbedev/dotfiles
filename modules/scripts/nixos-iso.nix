# nixos-iso: builds and writes the installer image.
_: {
  flake.modules.homeManager.script-nixos-iso =
    {
      config,
      pkgs,
      ...
    }:
    let
      # Same catalogue the hm wrapper renders its help from.
      hmSpec = pkgs.stubbe.hm;

      nixosIso = pkgs.stubbe.bashApp {
        name = "nixos-iso";
        text = ''
          set -euo pipefail

          flake_dir="''${NIXOS_FLAKE_DIR:-${config.stubbe.paths.dotfiles}}"
          out_link="''${NIXOS_ISO_OUT_LINK:-''${XDG_CACHE_HOME:-$HOME/.cache}/nixos-installer-iso}"

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
          ${hmSpec.renderSubHelp "iso"}

          Environment:
            NIXOS_FLAKE_DIR       Override the flake directory (default: ~/.stubbe)
            NIXOS_ISO_OUT_LINK    Override the build result link (default: ~/.cache/nixos-installer-iso)

          The ISO build always reads ~/.ssh impurely and embeds detected public
          and private SSH key files into /root/.ssh on the live image.
          EOF
          }

          build_iso() {
            nix build --impure "$flake_ref#installer-iso" --out-link "$out_link" "$@"
          }

          resolve_iso_path() {
            local dir
            dir=$(readlink -f "$out_link")
            echo "$dir"/iso/*.iso
          }

          print_iso_path() {
            build_iso "$@" >/dev/null
            resolve_iso_path
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

            if [[ "''${#nix_args[@]}" -gt 0 ]] || \
               ! { [[ -L "$out_link" ]] && [[ -e "$(readlink -f "$out_link" 2>/dev/null || true)" ]]; }; then
              build_iso "''${nix_args[@]}"
            else
              echo "Reusing existing ISO build: $(readlink -f "$out_link")"
            fi
            iso_path=$(resolve_iso_path)

            echo "Writing $iso_path to $device"
            iso_size=$(stat -c%s "$iso_path" 2>/dev/null || stat -f%z "$iso_path" 2>/dev/null || echo 0)
            if command -v pv >/dev/null 2>&1 && [[ "$iso_size" -gt 0 ]]; then
              pv -s "$iso_size" "$iso_path" | sudo dd of="$device" bs=16M conv=fsync
            else
              sudo dd if="$iso_path" of="$device" bs=16M status=progress conv=fsync
            fi
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
        '';
      };
    in
    {
      home.packages = [ nixosIso ];
    };
}
