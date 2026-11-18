{ inputs, ... }:
{
  flake.modules.homeManager.script-hix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cacheTargets = {
        nvim = {
          description = "Clear ~/.local/{share,state}/nvim and ~/.cache/nvim";
          dirs = [
            "$HOME/.local/share/nvim"
            "$HOME/.local/state/nvim"
            "$HOME/.cache/nvim"
          ];
        };
      };
      cacheTargetNames = lib.concatStringsSep ", " (lib.attrNames cacheTargets);

      hixCache = pkgs.stubbe.bashApp {
        name = "hix-cache";
        text = ''
          usage() {
            echo "Usage: hix cache <target>, target one of: ${cacheTargetNames}"
          }

          case "''${1:-}" in
          ${lib.concatStrings (
            lib.mapAttrsToList (name: target: ''
              ${name})
                echo ${lib.escapeShellArg "Clearing ${name} cache: ${target.description}"}
                rm -rf -- ${lib.concatMapStringsSep " " (dir: ''"${dir}"'') target.dirs}
                ;;
            '') cacheTargets
          )}
            -h|--help)
              usage
              ;;
            "")
              usage >&2
              exit 2
              ;;
            *)
              echo "hix cache: unknown target '$1' (want ${cacheTargetNames})" >&2
              exit 2
              ;;
          esac
        '';
      };

      hixClean = pkgs.stubbe.bashApp {
        name = "hix-clean";
        runtimeInputs = [ pkgs.fzf ];
        text = ''
          root="''${1:-$HOME}"

          echo "Scanning $root for reclaimable space (build artifacts, caches, core dumps)..." >&2

          paths=()
          while IFS= read -r -d ''' p; do paths+=("$p"); done < <(
            find "$root" -xdev \( -path '*/.git' -o -path "$HOME/.cache" \) -prune -o \
              \( -name node_modules -o -name target -o -name .next -o -name dist -o -name vendor -o -name .venv \) \
              -type d -print0 -prune 2>/dev/null
          )
          shopt -s nullglob dotglob
          for candidate in "$HOME"/core "$HOME"/core.[0-9]*; do
            [ -f "$candidate" ] && paths+=("$candidate")
          done
          paths+=("$HOME"/.cache/*)

          menu=($'(action)\tNix store garbage: old generations + unreachable paths (runs: hix gc)')
          if [ "''${#paths[@]}" -gt 0 ]; then
            while IFS= read -r line; do menu+=("$line"); done < <(
              du -sh -- "''${paths[@]}" 2>/dev/null | sort -rh
            )
          fi

          printf -v menu_text '%s\n' "''${menu[@]}"
          selection=$(fzf --multi \
            --header='TAB select, ENTER to review & delete. Regenerable build dirs, caches, core dumps, nix gc.' \
            --delimiter=$'\t' --with-nth=1,2 <<< "''${menu_text%$'\n'}")
          if [ -z "$selection" ]; then
            echo "hix clean: nothing selected"
            exit 0
          fi

          echo
          echo "About to remove:"
          printf '  %s\n' "''${selection//$'\n'/$'\n'  }"
          read -rp "Proceed? [y/N] " confirm
          if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "hix clean: aborted"
            exit 0
          fi

          collect_garbage=false
          targets=()
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
            ${lib.getExe config.programs.hix.package} gc
          fi

          echo "Done."
        '';
      };
    in
    {
      imports = [ inputs.hix.homeManagerModules.default ];

      programs.hix = {
        enable = true;
        flake = config.stubbe.paths.dotfiles;
        inherit (config.host) platform;
        attr = config.host.flakeAttr;
        commands = [
          {
            name = "clean";
            description = "Interactive fzf TUI to reclaim disk space (build dirs, caches, core dumps, nix gc) under [dir], default $HOME";
            exec = lib.getExe hixClean;
          }
          {
            name = "cache";
            description = "Wipe cached state (target: ${cacheTargetNames})";
            exec = lib.getExe hixCache;
            complete = lib.mapAttrsToList (name: target: {
              inherit name;
              inherit (target) description;
            }) cacheTargets;
          }
        ];
      };
    };
}
