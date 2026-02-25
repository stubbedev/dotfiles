_: {
  flake.modules.homeManager.packagesHm =
    {
      pkgs,
      config,
      ...
    }:
    let
      hmFlakeDir = "${config.home.homeDirectory}/.stubbe/src/nix/home-manager";
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
                        if ! has_cmd home-manager; then
                          echo "home-manager is not available on PATH" >&2
                          exit 1
                        fi
                        home-manager switch --flake "$hm_flake_ref" --impure "$@"
                        nh clean user -q
                        ;;
                      help|-h|--help)
                        usage
                        ;;
                      *)
                        if ! has_cmd home-manager; then
                          echo "home-manager is not available on PATH" >&2
                          exit 1
                        fi
                        home-manager --impure "$@"
                        nh clean user -q
                        ;;
                    esac
        '')
      ];
    };
}
