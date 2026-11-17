# hm: the wrapper around nixos-rebuild / nix-on-droid that every host drives.
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
      yq = lib.getExe pkgs.yq-go;
      sops = lib.getExe pkgs.sops;
      sshToAge = lib.getExe pkgs.ssh-to-age;

      usageText = ''
        Usage: hm <command> [args]

        Commands:
        ${hmSpec.renderExpandedHelp "wrapper"}

        ${hmSpec.renderExpandedHelp "rebuild"}
        ${hmSpec.renderHelp "meta"}

        All rebuild verbs use raw nixos-rebuild: no nh, no nom, and no
        --impure outside `hm iso` (the flake evaluates purely).

        On NixOS the build/activate verbs delegate to `nixos-rebuild
        <cmd> --flake <flake>#<host>`; the activating verbs add
        `--elevate sudo`, so evaluation and build run as you and only
        activation runs as root. The host attr is host.flakeAttr;
        override with HM_NIXOS_CONFIG=<attr>.

        On Android (nix-on-droid) switch and build delegate to
        `nix-on-droid <cmd> --flake <flake>#<host>`; the host attr is
        host.flakeAttr, since neither the hostname nor $USER names the
        configuration there. Every other verb errors.'';

      hm = pkgs.stubbe.bashApp {
        name = "hm";
        text = ''
          resolve_dir() {
            cd -P -- "$1" || { echo "hm: cannot resolve directory $1" >&2; return 1; }
            resolved_dir=$PWD
            cd - >/dev/null
          }

          resolve_dir "''${HM_FLAKE_DIR:-${config.stubbe.paths.dotfiles}}"
          hm_flake_dir=$resolved_dir
          hm_flake_ref="path:$hm_flake_dir"
          hm_sops_config="$hm_flake_dir/.sops.yaml"
          hm_host_attr=${lib.escapeShellArg config.host.flakeAttr}
          hm_short_hostname="''${HOSTNAME%%.*}"
          hm_ssh_pubkey="$HOME/.ssh/id_ed25519.pub"

          flake_sops() {
            ${sops} --config "$hm_sops_config" "$@"
          }

          write_file_atomically() {
            printf '%s' "$2" > "$1.new"
            mv -- "$1.new" "$1"
          }

          is_nix_on_droid() {
            ${lib.boolToString (config.host.platform == "android")}
          }

          run_hm_subcmd() {
            local subcmd="$1"; shift

            if is_nix_on_droid; then
              case "$subcmd" in
                switch|build)
                  nix-on-droid "$subcmd" --flake "$hm_flake_ref#$hm_host_attr" "$@"
                  ;;
                *)
                  echo "hm $subcmd: unavailable on Android. Supported rebuild verbs: switch, build." >&2
                  return 1
                  ;;
              esac
              return
            fi

            local ref="$hm_flake_ref#''${HM_NIXOS_CONFIG:-$hm_host_attr}"
            case "$subcmd" in
              repl)
                nix repl "$ref" "$@"
                ;;
              switch|boot|test|dry-activate)
                nixos-rebuild "$subcmd" --elevate sudo --flake "$ref" "$@"
                ;;
              build|dry-build|build-vm|build-vm-with-bootloader)
                nixos-rebuild "$subcmd" --flake "$ref" "$@"
                ;;
              *)
                echo "hm $subcmd: unavailable on NixOS. Supported subcommands: ${hmSpec.nixosVerbs}." >&2
                return 1
                ;;
            esac
          }

          run_rollback() {
            if is_nix_on_droid; then
              nix-on-droid rollback
            else
              nixos-rebuild switch --rollback --elevate sudo "$@"
            fi
          }

          run_gc() {
            [ "$#" -gt 0 ] || set -- -d
            ${lib.optionalString (config.host.platform == "nixos") "sudo "}nix-collect-garbage "$@"
          }

          run_generations() {
            if is_nix_on_droid; then
              nix-on-droid generations "$@"
            else
              nixos-rebuild list-generations "$@"
            fi
          }

          sudo_keepalive_pid=""
          start_sudo_keepalive() {
            [ -n "$sudo_keepalive_pid" ] && return 0
            echo "Requesting sudo..."
            sudo -v || return 1
            while true; do
              sleep 50
              kill -0 "$$" 2>/dev/null || exit 0
              sudo -n true 2>/dev/null || true
            done </dev/null >/dev/null 2>&1 &
            sudo_keepalive_pid=$!
            # shellcheck disable=SC2064
            trap "kill $sudo_keepalive_pid 2>/dev/null || true" EXIT
          }

          prime_sudo_nixos() {
            if ! is_nix_on_droid; then
              start_sudo_keepalive
            fi
          }

          flake_git() {
            git -C "$hm_flake_dir" \
              -c merge.flakelock.name="keep current flake.lock (regenerated)" \
              -c merge.flakelock.driver=true \
              "$@"
          }

          pull_flake_repo() {
            flake_git pull --rebase --autostash --quiet && return 0
            local rebase_dir
            rebase_dir=$(flake_git rev-parse --git-path rebase-merge)
            if [ -d "$rebase_dir" ] || [ -d "''${rebase_dir%-merge}-apply" ]; then
              flake_git rebase --abort
            fi
            return 1
          }

          commit_flake_lock() {
            local has_upstream="$1"
            flake_git diff --quiet -- flake.lock && return 0
            flake_git commit --quiet -m "chore: update flake.lock" -- flake.lock
            echo "Committed updated flake.lock"
            [ "$has_upstream" = true ] || return 0
            flake_git push --quiet 2>/dev/null && return 0
            if pull_flake_repo && flake_git push --quiet; then
              return 0
            fi
            echo "flake.lock committed locally; push failed (resolve manually)" >&2
          }

          push_to_cache() {
            ${
              if config.features.development then
                ''
                  local tokenFile="$hm_flake_dir/secrets/xilo-token"
                  if [ ! -f "$tokenFile" ]; then
                    echo "cache push: secrets/xilo-token missing — run 'hm secret set xilo-token'. Skipping." >&2
                    return 0
                  fi

                  local token
                  token=$(${sops} --decrypt \
                    --input-type binary --output-type binary "$tokenFile" 2>/dev/null) || {
                    echo "cache push: could not decrypt xilo-token; skipping." >&2
                    return 0
                  }

                  resolve_dir ${
                    {
                      android = ''"$HOME/.nix-profile"'';
                      nixos = "/run/current-system";
                    }
                    .${config.host.platform}
                  }
                  local path=$resolved_dir

                  echo "Pushing ''${path##*/} closure to the cache…"
                  XILO_URL="https://nix.stubbe.dev" XILO_TOKEN="$token" \
                    ${lib.getExe' pkgs.xilo "xilo"} push default "$path" --quiet \
                    || echo "cache push failed (non-fatal)." >&2
                ''
              else
                "return 0"
            }
          }

          update_system() {
            echo "Updating nix inputs"
            if [ ! -e "$hm_flake_dir/.git" ]; then
              nix flake update --flake "$hm_flake_ref" --quiet
              return
            fi
            local has_upstream=false
            if flake_git rev-parse --verify --quiet '@{u}' >/dev/null; then
              has_upstream=true
              pull_flake_repo ||
                echo "hm: pulling $hm_flake_dir from upstream failed; updating against the local checkout" >&2
            fi
            nix flake update --flake "$hm_flake_ref" --quiet
            commit_flake_lock "$has_upstream"
          }

          usage() {
            printf '%s\n' ${lib.escapeShellArg usageText}
          }

          hm_whoami() {
            local pubkey
            pubkey=$(${sshToAge} < "$hm_ssh_pubkey") || {
              echo "hm whoami: could not derive an age pubkey from $hm_ssh_pubkey" >&2
              return 1
            }
            printf '%s %s\n' "$hm_short_hostname" "$pubkey"
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
              printf '%s\n' >&2 \
                "Usage:" \
                "  hm trust <name> <pubkey>      # explicit" \
                "  hm trust <pubkey>             # auto-name from hostname or pubkey suffix" \
                "  <cmd> | hm trust              # e.g. ssh laptop2 hm whoami | hm trust"
              return 2
            fi

            if [ -z "$name" ]; then
              local local_pubkey=""
              if [ -f "$hm_ssh_pubkey" ]; then
                local_pubkey=$(${sshToAge} < "$hm_ssh_pubkey")
              fi
              if [ -n "$local_pubkey" ] && [ "$pubkey" = "$local_pubkey" ]; then
                name="$hm_short_hostname"
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

            local -a original_lines
            mapfile -t original_lines < "$hm_sops_config" || {
              echo "hm trust: cannot read $hm_sops_config" >&2
              return 1
            }
            local original updated
            printf -v original '%s\n' "''${original_lines[@]}"
            updated=$(PUBKEY="$pubkey" NAME="$name" ${yq} '
                select([.creation_rules[].key_groups[].age[]] | any_c(. == strenv(PUBKEY)) | not)
                | (.creation_rules[].key_groups[].age) += [strenv(PUBKEY)]
                | (.creation_rules[].key_groups[].age[] | select(. == strenv(PUBKEY))) line_comment = strenv(NAME)
              ' "$hm_sops_config") || {
              echo "hm trust: could not add $pubkey to the age recipients in $hm_sops_config" >&2
              return 1
            }
            if [ -z "$updated" ]; then
              echo "hm trust: $pubkey already present in .sops.yaml — nothing to do."
              return 0
            fi
            write_file_atomically "$hm_sops_config" "$updated"$'\n'

            echo "Added $name → $pubkey to .sops.yaml"

            shopt -s nullglob
            local secret count=0
            for secret in "$hm_flake_dir"/secrets/*; do
              [ -f "$secret" ] || continue
              echo "Re-wrapping ''${secret##*/}"
              if ! flake_sops updatekeys --yes "$secret"; then
                write_file_atomically "$hm_sops_config" "$original"
                echo "hm trust: rolled back .sops.yaml" >&2
                return 1
              fi
              count=$((count + 1))
            done

            echo
            printf '%s\n' \
              "Trusted $name across $count secret file(s)." \
              "Review:  git -C \"$hm_flake_dir\" diff -- .sops.yaml secrets/" \
              "Commit:  git -C \"$hm_flake_dir\" add .sops.yaml secrets/ && \\" \
              "         git -C \"$hm_flake_dir\" commit -m \"trust: add $name age recipient\""
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
              ""|-h|--help)
                printf '%s\n' >&2 "Usage: hm cache <target>" "" "Targets:" ${lib.escapeShellArg (hmSpec.renderSubHelp "cache")}
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

            echo "Scanning $root for reclaimable space (build artifacts, caches, core dumps)..." >&2

            local -a paths=()
            while IFS= read -r -d ''' p; do paths+=("$p"); done < <(
              find "$root" -xdev \( -path '*/.git' -o -path "$HOME/.cache" \) -prune -o \
                \( -name node_modules -o -name target -o -name .next -o -name dist -o -name vendor -o -name .venv \) \
                -type d -print0 -prune 2>/dev/null
            )
            shopt -s nullglob dotglob
            local candidate
            for candidate in "$HOME"/core "$HOME"/core.[0-9]*; do
              [ -f "$candidate" ] && paths+=("$candidate")
            done
            paths+=("$HOME"/.cache/*)

            local -a menu=($'(action)\tNix store garbage — old generations + unreachable paths (runs: hm gc)')
            if [ "''${#paths[@]}" -gt 0 ]; then
              while IFS= read -r line; do menu+=("$line"); done < <(
                du -sh -- "''${paths[@]}" 2>/dev/null | sort -rh
              )
            fi

            local selection
            local menu_text
            printf -v menu_text '%s\n' "''${menu[@]}"
            selection=$(fzf --multi \
              --header='TAB select, ENTER to review & delete. Regenerable build dirs, caches, core dumps, nix gc.' \
              --delimiter=$'\t' --with-nth=1,2 <<< "''${menu_text%$'\n'}")
            [ -n "$selection" ] || { echo "hm clean: nothing selected"; return 0; }

            echo
            echo "About to remove:"
            printf '  %s\n' "''${selection//$'\n'/$'\n'  }"
            read -rp "Proceed? [y/N] " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { echo "hm clean: aborted"; return 0; }

            local size target collect_garbage=false
            local -a targets=()
            while IFS=$'\t' read -r size target; do
              if [ "$size" = "(action)" ]; then
                collect_garbage=true
                continue
              fi
              echo "Removing $target ($size)..."
              targets+=("$target")
            done <<< "$selection"
            if [ "''${#targets[@]}" -gt 0 ]; then
              rm -rf -- "''${targets[@]}"
            fi
            if [ "$collect_garbage" = true ]; then
              run_gc
            fi

            echo "Done."
          }

          hm_secret() {
            local action="''${1:-}"
            local name="''${2:-}"
            if [ -z "$action" ] || [ -z "$name" ]; then
              echo "Usage: hm secret {${hmSpec.subNames "secret"}} <name>" >&2
              return 2
            fi
            if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
              echo "hm secret: name '$name' must match [A-Za-z0-9][A-Za-z0-9._-]* (a file directly under secrets/)" >&2
              return 2
            fi
            local path="$hm_flake_dir/secrets/$name"
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
                flake_sops --input-type binary --output-type binary "$path"
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
                elif IFS= read -rd ''' pw; then
                  echo "hm secret set: value contains a NUL byte" >&2
                  return 1
                else
                  pw="''${pw%"''${pw##*[!$'\n']}"}"
                fi
                if [ -z "$pw" ]; then
                  echo "hm secret set: refusing to write empty value" >&2
                  return 1
                fi
                local tmp="$path.new"
                if ! printf '%s' "$pw" | flake_sops --encrypt \
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
                flake_sops --rotate -i \
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
              ${
                if config.features.ops then
                  ''nixos-iso "$@"''
                else
                  ''
                    echo "hm iso: the installer ISO builder is part of features.ops, which this host disables." >&2
                    exit 2
                  ''
              }
              ;;
            help|-h|--help)
              usage
              ;;
            switch)
              shift
              prime_sudo_nixos
              run_hm_subcmd switch "$@" && push_to_cache
              ;;
            boot|test)
              subcmd="$1"
              shift
              run_hm_subcmd "$subcmd" "$@"
              ;;
            build|dry-build|dry-activate|build-vm|build-vm-with-bootloader|repl)
              subcmd="$1"
              shift
              run_hm_subcmd "$subcmd" "$@"
              ;;
            rollback)
              shift
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
              echo "hm: unknown command '$1'. Try 'hm help'." >&2
              exit 2
              ;;
          esac
        '';
      };
    in
    {
      home.packages = [ hm ];
    };
}
