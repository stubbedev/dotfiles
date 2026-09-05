# hm: the wrapper around home-manager/nixos-rebuild that every host drives.
# nh stays on PATH: the wrapper shells out to it, and it is useful directly.
_: {
  flake.modules.homeManager.script-hm =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Defined in modules/core/lib/hm-commands.nix so this wrapper and the zsh
      # completion in modules/shell.nix cannot disagree.
      hmSpec = pkgs.stubbe.hm;

      hm = pkgs.stubbe.bashApp {
        name = "hm";
        text = ''
          set -euo pipefail

          hm_flake_dir="''${HM_FLAKE_DIR:-${config.stubbe.paths.dotfiles}}"

          has_cmd() {
            command -v "$1" >/dev/null 2>&1
          }

          if has_cmd readlink; then
            hm_flake_dir=$(readlink -f "$hm_flake_dir" 2>/dev/null || echo "$hm_flake_dir")
          fi

          hm_flake_ref="path:$hm_flake_dir"

          is_nixos() {
            [ -r /etc/os-release ] && grep -q '^ID=nixos' /etc/os-release
          }

          nixos_attr() {
            echo "''${HM_NIXOS_CONFIG:-$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)}"
          }

          run_nh() {
            local subcmd="$1"; shift
            local sub=home ref="$hm_flake_ref"
            if is_nixos; then
              sub=os
              [ -n "''${HM_NIXOS_CONFIG:-}" ] && ref="$ref#$HM_NIXOS_CONFIG"
            fi
            nh "$sub" "$subcmd" "$ref" -- --impure "$@"
          }

          run_hm_subcmd() {
            local subcmd="$1"; shift

            case "$subcmd" in
              switch|boot|test|build|repl)
                if ! is_nixos; then
                  case "$subcmd" in
                    boot|test)
                      echo "hm $subcmd: NixOS-only (no home-manager CLI equivalent)." >&2
                      return 1
                      ;;
                  esac
                fi
                run_nh "$subcmd" "$@"
                return
                ;;
            esac

            if is_nixos; then
              local prefix=()
              case "$subcmd" in
                dry-activate)
                  prefix=(sudo)
                  ;;
                dry-build|build-vm|build-vm-with-bootloader)
                  ;;
                *)
                  echo "hm $subcmd: unavailable on NixOS. Supported subcommands: ${hmSpec.nixosVerbs}." >&2
                  return 1
                  ;;
              esac
              "''${prefix[@]}" nixos-rebuild "$subcmd" --flake "$hm_flake_ref#$(nixos_attr)" --impure "$@"
            else
              case "$subcmd" in
                boot|test|dry-activate|dry-build|build-vm|build-vm-with-bootloader|repl)
                  echo "hm $subcmd: NixOS-only (no home-manager CLI equivalent)." >&2
                  return 1
                  ;;
                *)
                  home-manager "$subcmd" --flake "$hm_flake_ref" --impure "$@"
                  ;;
              esac
            fi
          }

          run_rollback() {
            if is_nixos; then
              nh os rollback "$@"
            else
              echo "hm rollback: not implemented for standalone home-manager. Use 'home-manager generations' to list, then run '<gen>/activate' from the desired generation." >&2
              return 2
            fi
          }

          run_gc() {
            if [ "$#" -eq 0 ]; then
              if is_nixos; then
                nh clean all
              else
                nh clean user
              fi
              return
            fi

            if is_nixos; then
              sudo nix-collect-garbage "$@"
            else
              nix-collect-garbage "$@"
            fi
          }

          run_generations() {
            if is_nixos; then
              nh os info "$@"
            else
              home-manager generations "$@"
            fi
          }


          ensure_sudo() {
            if [[ "''${1:-}" == "true" ]]; then
              echo "Requesting sudo..."
              sudo -v
            fi
          }

          prime_sudo_nixos() {
            if is_nixos && has_cmd sudo; then
              echo "Requesting sudo..."
              sudo -v
            fi
          }

          flake_git() {
            git -C "$hm_flake_dir" "$@"
          }

          flake_in_git() {
            has_cmd git && flake_git rev-parse --is-inside-work-tree >/dev/null 2>&1
          }

          flake_has_upstream() {
            flake_git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1
          }

          ensure_flakelock_driver() {
            flake_git config merge.flakelock.name "keep current flake.lock (regenerated)" >/dev/null 2>&1 || true
            flake_git config merge.flakelock.driver true >/dev/null 2>&1 || true
          }

          sync_flake_repo() {
            flake_in_git || return 0
            flake_has_upstream || return 0
            flake_git fetch --quiet || return 0
            flake_git pull --rebase --autostash --quiet || {
              flake_git rebase --abort >/dev/null 2>&1 || true
            }
          }

          commit_flake_lock() {
            flake_in_git || return 0
            flake_git diff --quiet -- flake.lock 2>/dev/null && return 0   # unchanged
            flake_git add -- flake.lock || return 0
            flake_git commit -m "chore: update flake.lock" -- flake.lock >/dev/null || return 0
            echo "Committed updated flake.lock"
            flake_has_upstream || return 0
            flake_git push --quiet 2>/dev/null && return 0
            flake_git pull --rebase --autostash --quiet || {
              flake_git rebase --abort >/dev/null 2>&1 || true
              echo "flake.lock committed locally; push failed (resolve manually)" >&2
              return 0
            }
            flake_git push --quiet 2>/dev/null || \
              echo "flake.lock committed locally; push failed (resolve manually)" >&2
          }

          push_to_cache() {
            has_cmd ${lib.getExe' pkgs.xilo "xilo"} || return 0

            local tokenFile="$hm_flake_dir/secrets/xilo-token"
            if [ ! -f "$tokenFile" ]; then
              echo "cache push: secrets/xilo-token missing — run 'hm secret set xilo-token'. Skipping." >&2
              return 0
            fi

            local ageKey token
            ageKey=$(${lib.getExe pkgs.ssh-to-age} -private-key -i "$HOME/.ssh/id_ed25519" 2>/dev/null) || return 0
            token=$(SOPS_AGE_KEY="$ageKey" ${lib.getExe pkgs.sops} --decrypt \
              --input-type binary --output-type binary "$tokenFile" 2>/dev/null) || {
              echo "cache push: could not decrypt xilo-token; skipping." >&2
              return 0
            }

            local path
            if is_nixos; then
              path=$(readlink -f /run/current-system 2>/dev/null)
            else
              path=$(readlink -f "$HOME/.local/state/nix/profiles/home-manager" 2>/dev/null)
            fi
            [ -n "$path" ] && [ -e "$path" ] || return 0

            echo "Pushing $(basename "$path") closure to the cache…"
            XILO_URL="https://nix.stubbe.dev" XILO_TOKEN="$token" \
              ${lib.getExe' pkgs.xilo "xilo"} push default "$path" --quiet \
              || echo "cache push failed (non-fatal)." >&2
          }

          release_pinned_repos="PHPantom-dev/phpantom_lsp"
          bump_release_pins() {
            local repo latest name bumped=""
            has_cmd curl || return 0
            for repo in $release_pinned_repos; do
              latest=$(curl -fsSL --max-time 10 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
                | grep -om1 '"tag_name": *"[^"]*"' | cut -d'"' -f4) || true
              [ -n "$latest" ] || continue
              grep -q "github:$repo/$latest" "$hm_flake_dir/flake.nix" && continue
              sed -i "s|github:$repo/[^\"]*|github:$repo/$latest|" "$hm_flake_dir/flake.nix"
              name=''${repo##*/}
              echo "Bumped $name pin to $latest"
              bumped="$bumped $name→$latest"
            done
            [ -n "$bumped" ] || return 0
            if flake_in_git; then
              flake_git add -- flake.nix >/dev/null 2>&1 || return 0
              flake_git commit -qm "chore: bump release pins:$bumped" -- flake.nix >/dev/null 2>&1 || true
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
              sudo apt-get -qq update
              sudo DEBIAN_FRONTEND=noninteractive apt-get -qq -y upgrade
              sudo apt-get -qq -y autoremove
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
              if flake_in_git; then
                ensure_flakelock_driver
                sync_flake_repo
              fi
              bump_release_pins
              nix flake update --flake "$hm_flake_ref" --quiet
              commit_flake_lock
            fi

            if has_cmd nix-channel; then
              nix-channel --update >/dev/null 2>&1 || true
            fi
          }

          usage() {
            cat <<'EOF'
          Usage: hm <command> [args]

          Commands:
          ${hmSpec.renderExpandedHelp "wrapper"}

          ${hmSpec.renderExpandedHelp "rebuild"}
          ${hmSpec.renderHelp "meta"}

          switch/boot/test/build/repl, gc, generations, and rollback route through
          `nh` (version diff + progress output). The remaining verbs (dry-build,
          dry-activate, build-vm*, news, instantiate) use raw nixos-rebuild/home-manager.

          On NixOS the build/activate verbs delegate to `[sudo ]nixos-rebuild
          <cmd> --flake <flake>#<host> --impure`. The host attr defaults to
          `hostname -s`; override with HM_NIXOS_CONFIG=<attr>. Verbs without
          a NixOS counterpart (news/instantiate) error on NixOS; verbs without
          a home-manager counterpart (boot/test/dry-activate/dry-build/build-vm
          /repl) error on non-NixOS. Unknown args fall through to home-manager
          on non-NixOS.
          EOF
          }

          hm_whoami() {
            if [ ! -f "$HOME/.ssh/id_ed25519.pub" ]; then
              echo "hm whoami: ~/.ssh/id_ed25519.pub not found" >&2
              return 1
            fi
            local pubkey host
            pubkey=$(${lib.getExe pkgs.ssh-to-age} < "$HOME/.ssh/id_ed25519.pub")
            host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")
            printf '%s %s\n' "$host" "$pubkey"
          }

          hm_trust() {
            local name="" pubkey=""

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

            if [ -z "$name" ]; then
              local local_pubkey=""
              if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
                local_pubkey=$(${lib.getExe pkgs.ssh-to-age} < "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || true)
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

            if ! ${lib.getExe pkgs.age} -r "$pubkey" -o /dev/null </dev/null 2>/dev/null; then
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

            local backup
            backup=$(mktemp)
            cp "$sops_yaml" "$backup"

            rollback() {
              cp "$backup" "$sops_yaml"
              rm -f "$backup"
              echo "hm trust: rolled back .sops.yaml" >&2
            }

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

            shopt -s nullglob
            local secret count=0
            for secret in "$hm_flake_dir"/secrets/*; do
              [ -f "$secret" ] || continue
              echo "Re-wrapping $(basename "$secret")"
              if ! ${lib.getExe pkgs.sops} updatekeys --yes "$secret"; then
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

          hm_cache() {
            local target="''${1:-}"
            case "$target" in
              nvim)
                echo "Clearing nvim cache (~/.local/{share,state}/nvim and ~/.cache/nvim)..."
                rm -rf \
                  "$HOME/.local/share/nvim" \
                  "$HOME/.local/state/nvim" \
                  "$HOME/.cache/nvim"
                ;;
              locks)
                local lock_dir="$HOME/.local/state/nix/home-manager"
                if [ -d "$lock_dir" ]; then
                  local count
                  count=$(find "$lock_dir" -maxdepth 1 -name '*.lock.sum' -type f | wc -l)
                  if [ "$count" -gt 0 ]; then
                    echo "Wiping $count activation lock(s) at $lock_dir..."
                    find "$lock_dir" -maxdepth 1 -name '*.lock.sum' -type f -delete
                  else
                    echo "No activation locks under $lock_dir; nothing to do."
                  fi
                else
                  echo "$lock_dir does not exist; nothing to do."
                fi
                echo "Next 'hm switch' will re-run each privileged activation."
                ;;
              all)
                hm_cache nvim
                ;;
              ""|-h|--help)
                cat <<EOF >&2
          Usage: hm cache <target>

          Targets:
          ${hmSpec.renderSubHelp "cache"}
          EOF
                [ -z "$target" ] && return 2 || return 0
                ;;
              *)
                echo "hm cache: unknown target '$target' (want ${hmSpec.subNames "cache"})" >&2
                return 2
                ;;
            esac
          }

          hm_clean() {
            local root="''${1:-$HOME}"
            has_cmd fzf || { echo "hm clean: fzf not found" >&2; return 1; }

            echo "Scanning $root for reclaimable space (build artifacts, caches, core dumps)..." >&2

            local -a paths=()
            while IFS= read -r -d ''' p; do paths+=("$p"); done < <(
              find "$root" -xdev \( -path '*/.git' -o -path "$HOME/.cache" \) -prune -o \
                \( -name node_modules -o -name target -o -name .next -o -name dist -o -name vendor -o -name .venv \) \
                -type d -print0 -prune 2>/dev/null
            )
            while IFS= read -r -d ''' p; do paths+=("$p"); done < <(
              find "$HOME" -maxdepth 1 \( -name 'core.[0-9]*' -o -name 'core' \) -type f -print0 2>/dev/null
            )
            while IFS= read -r -d ''' p; do paths+=("$p"); done < <(
              find "$HOME/.cache" -mindepth 1 -maxdepth 1 -print0 2>/dev/null
            )

            local -a menu=($'(action)\tNix store garbage — old generations + unreachable paths (runs: hm gc)')
            if [ "''${#paths[@]}" -gt 0 ]; then
              while IFS= read -r line; do menu+=("$line"); done < <(
                du -sh -- "''${paths[@]}" 2>/dev/null | sort -rh
              )
            fi

            local selection
            selection=$(printf '%s\n' "''${menu[@]}" | fzf --multi \
              --header='TAB select, ENTER to review & delete. Regenerable build dirs, caches, core dumps, nix gc.' \
              --delimiter=$'\t' --with-nth=1,2)
            [ -n "$selection" ] || { echo "hm clean: nothing selected"; return 0; }

            echo
            echo "About to remove:"
            echo "$selection" | sed 's/^/  /'
            read -rp "Proceed? [y/N] " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { echo "hm clean: aborted"; return 0; }

            local size target
            while IFS=$'\t' read -r size target; do
              if [ "$size" = "(action)" ]; then
                run_gc
                continue
              fi
              echo "Removing $target ($size)..."
              rm -rf -- "$target"
            done <<< "$selection"

            echo "Done."
          }

          hm_secret() {
            local action="''${1:-}"
            local name="''${2:-}"
            if [ -z "$action" ] || [ -z "$name" ]; then
              echo "Usage: hm secret {${hmSpec.subNames "secret"}} <name>" >&2
              return 2
            fi
            local path="$hm_flake_dir/secrets/$name"
            # Secrets carry the extension of their plaintext (npmrc.ini,
            # ds-mcp.json) so $EDITOR gets a filetype. Resolve a bare name to
            # it, or `edit` would silently create an extensionless duplicate.
            if [ ! -e "$path" ]; then
              local -a hits=()
              local hit
              for hit in "$hm_flake_dir/secrets/$name".*; do
                [ -e "$hit" ] && hits+=("$hit")
              done
              if [ "''${#hits[@]}" -eq 1 ]; then
                path="''${hits[0]}"
                name="''${path##*/}"
              elif [ "''${#hits[@]}" -gt 1 ]; then
                echo "hm secret: '$name' is ambiguous: ''${hits[*]##*/}" >&2
                return 2
              fi
            fi
            case "$action" in
              edit)
                ${lib.getExe pkgs.sops} --input-type binary --output-type binary "$path"
                ;;
              set)
                local pw=""
                if [ -t 0 ]; then
                  read -srp "New value for $name: " pw
                  echo
                  local pw2=""
                  read -srp "Confirm: " pw2
                  echo
                  if [ "$pw" != "$pw2" ]; then
                    echo "hm secret set: values do not match" >&2
                    return 1
                  fi
                  unset pw2
                else
                  pw=$(cat)
                fi
                if [ -z "$pw" ]; then
                  echo "hm secret set: refusing to write empty value" >&2
                  return 1
                fi
                local tmp="$path.new"
                if ! printf '%s' "$pw" | ${lib.getExe pkgs.sops} --encrypt \
                    --input-type binary --output-type binary \
                    --filename-override "$path" /dev/stdin > "$tmp"; then
                  rm -f "$tmp"
                  unset pw
                  echo "hm secret set: encryption failed" >&2
                  return 1
                fi
                mv "$tmp" "$path"
                unset pw
                echo "Updated secrets/$name. Run 'hm switch' to deploy, then commit."
                ;;
              rotate)
                if [ ! -f "$path" ]; then
                  echo "hm secret rotate: $path does not exist" >&2
                  return 1
                fi
                ${lib.getExe pkgs.sops} --rotate -i \
                  --input-type binary --output-type binary "$path"
                echo "Re-rolled data key for $name. Recipients unchanged."
                ;;
              *)
                echo "hm secret: unknown action '$action' (want edit|set|rotate)" >&2
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
              prime_sudo_nixos
              update_system
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              run_hm_subcmd switch "$@" && push_to_cache
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
            cache)
              shift
              hm_cache "$@"
              ;;
            clean)
              shift
              hm_clean "$@"
              ;;
            iso)
              shift
              nixos-iso "$@"
              ;;
            help|-h|--help)
              usage
              ;;
            switch)
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              shift
              prime_sudo_nixos
              run_hm_subcmd switch "$@" && push_to_cache
              ;;
            boot|test|build|dry-build|dry-activate|build-vm|build-vm-with-bootloader|repl|news|instantiate)
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              subcmd="$1"
              shift
              run_hm_subcmd "$subcmd" "$@"
              ;;
            rollback)
              shift
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              run_rollback "$@"
              ;;
            gc)
              shift
              run_gc "$@"
              ;;
            generations)
              shift
              run_generations "$@"
              ;;
            "")
              usage
              exit 2
              ;;
            *)
              rm -f "$HOME/.gtkrc-2.0" >/dev/null 2>&1
              if is_nixos; then
                echo "hm: '$1' is not supported on NixOS — the home-manager CLI is not available in submodule mode. Try 'hm help'." >&2
                exit 2
              fi
              home-manager --impure "$@"
              ;;
          esac
        '';
      };
    in
    {
      home.packages = [
        hm
        pkgs.nh
      ];
    };
}
