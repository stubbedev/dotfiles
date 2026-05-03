_: {
  flake.modules.homeManager.packagesHm =
    {
      pkgs,
      config,
      ...
    }:
    let
      hmFlakeDir = "${config.home.homeDirectory}/.stubbe/src/nix/home-manager";
      nixosFlakeDir = "${config.home.homeDirectory}/.stubbe/src/nix/nixos";
    in
    {
      home.packages = [
        (pkgs.writeShellScriptBin "hm" ''
                    set -euo pipefail

                    hm_flake_dir="''${HM_FLAKE_DIR:-${hmFlakeDir}}"

                    has_cmd() {
                      command -v "$1" >/dev/null 2>&1
                    }

                    if has_cmd readlink; then
                      hm_flake_dir=$(readlink -f "$hm_flake_dir" 2>/dev/null || echo "$hm_flake_dir")
                    fi

                    hm_flake_repo_root="$hm_flake_dir"
                    hm_flake_subdir=""
                    if [[ "$hm_flake_dir" == */src/nix/home-manager ]]; then
                      hm_flake_repo_root="''${hm_flake_dir%/src/nix/home-manager}"
                      hm_flake_subdir="src/nix/home-manager"
                    fi

                    if [[ -n "$hm_flake_subdir" ]]; then
                      hm_flake_ref="path:$hm_flake_repo_root?dir=$hm_flake_subdir"
                    else
                      hm_flake_ref="path:$hm_flake_dir"
                    fi

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
            update   Update system package managers and nix inputs
            upgrade  Update system packages and apply home-manager switch
            help     Show this help message

          Other args are passed through to home-manager.
          EOF
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
                      help|-h|--help)
                        usage
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

          nixos_flake_dir="''${NIXOS_FLAKE_DIR:-${nixosFlakeDir}}"
          out_link="''${NIXOS_ISO_OUT_LINK:-$PWD/result-nixos-installer-iso}"

          has_cmd() {
            command -v "$1" >/dev/null 2>&1
          }

          if has_cmd readlink; then
            nixos_flake_dir=$(readlink -f "$nixos_flake_dir" 2>/dev/null || echo "$nixos_flake_dir")
          fi

          nixos_flake_repo_root="$nixos_flake_dir"
          nixos_flake_subdir=""
          if [[ "$nixos_flake_dir" == */src/nix/nixos ]]; then
            nixos_flake_repo_root="''${nixos_flake_dir%/src/nix/nixos}"
            nixos_flake_subdir="src/nix/nixos"
          fi

          if [[ -n "$nixos_flake_subdir" ]]; then
            nixos_flake_ref="path:$nixos_flake_repo_root?dir=$nixos_flake_subdir"
          else
            nixos_flake_ref="path:$nixos_flake_dir"
          fi

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
            NIXOS_FLAKE_DIR       Override the NixOS flake directory
            NIXOS_ISO_OUT_LINK    Override the build result link

          The ISO build always reads ~/.ssh impurely and embeds detected public
          and private SSH key files into /root/.ssh on the live image.
          EOF
          }

          build_iso() {
            nix build --impure "$nixos_flake_ref#installer-iso" --out-link "$out_link" "$@"
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
