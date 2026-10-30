# nixos-iso: builds and writes the installer image.
_: {
  flake.modules.homeManager.script-nixos-iso =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Same catalogue the hm wrapper renders its help from.
      hmSpec = pkgs.stubbe.hm;

      nixosIso = pkgs.stubbe.bashApp {
        name = "nixos-iso";
        text = ''
          flake_dir=$(realpath -e "''${NIXOS_FLAKE_DIR:-${config.stubbe.paths.dotfiles}}")
          out_link="''${NIXOS_ISO_OUT_LINK:-${config.xdg.cacheHome}/nixos-installer-iso}"
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
               ! [[ -e "$out_link" ]]; then
              build_iso "''${nix_args[@]}"
            else
              echo "Reusing existing ISO build: $(readlink -f "$out_link")"
            fi
            iso_path=$(resolve_iso_path)

            echo "Writing $iso_path to $device"
            sudo dd if="$iso_path" of="$device" bs=16M status=progress conv=fsync
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
      home.packages = lib.optionals config.features.ops [ nixosIso ];
    };
}
