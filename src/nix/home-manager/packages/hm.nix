{ pkgs, config, ... }:
let hmFlakeDir = "${config.home.homeDirectory}/.stubbe/src/nix/home-manager";
in
[
  (pkgs.writeShellScriptBin "hm" ''
        #!/usr/bin/env bash
        set -euo pipefail

        hm_flake_dir="''${HM_FLAKE_DIR:-${hmFlakeDir}}"

        has_cmd() {
          command -v "$1" >/dev/null 2>&1
        }

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
            nix flake update --flake "$hm_flake_dir"
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
            home-manager switch --flake "$hm_flake_dir" --impure "$@"
            ;;
          help|-h|--help)
            usage
            ;;
          *)
            if ! has_cmd home-manager; then
              echo "home-manager is not available on PATH" >&2
              exit 1
            fi
            exec home-manager "$@"
            ;;
        esac
  '')
]
