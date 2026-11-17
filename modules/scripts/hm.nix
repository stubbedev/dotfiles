_: {
  stubbe.pkgsLib.hm =
    { final, lib, ... }:
    final.buildGoModule {
      pname = "hm";
      version = "1.0.0";
      src = lib.fileset.toSource {
        root = ../../src/hm;
        fileset = ../../src/hm;
      };
      vendorHash = "sha256-3aKtF+kUeeFpbCaeK4fBXq2fH1mg2C3qsNzedS5ldJU=";
      env.CGO_ENABLED = 0;
      ldflags = [
        "-s"
        "-w"
      ];
      nativeBuildInputs = [
        final.installShellFiles
        final.makeWrapper
      ];
      nativeCheckInputs = [
        final.age
        final.git
        final.openssh
        final.sops
        final.ssh-to-age
      ];
      preCheck = ''
        unformatted=$(find . -path ./vendor -prune -o -name '*.go' -print0 | xargs -0 gofmt -l)
        if [ -n "$unformatted" ]; then
          echo "gofmt: unformatted files: $unformatted" >&2
          exit 1
        fi
        go vet ./...
      '';
      postInstall = ''
        installShellCompletion --cmd hm \
          --zsh <($out/bin/hm completion zsh) \
          --bash <($out/bin/hm completion bash) \
          --fish <($out/bin/hm completion fish)
        wrapProgram $out/bin/hm --prefix PATH : ${
          lib.makeBinPath [
            final.age
            final.sops
            final.ssh-to-age
          ]
        }
      '';
      meta.mainProgram = "hm";
    };

  flake.modules.homeManager.script-hm =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      choiceOptions = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "The argument offered for completion.";
        };
        description = lib.mkOption {
          type = lib.types.str;
          description = "Its description in the completion menu.";
        };
      };

      commandType = lib.types.submodule {
        options = choiceOptions // {
          exec = lib.mkOption {
            type = lib.types.str;
            description = "Absolute path of the program `hm <name> [args]` runs with the arguments.";
          };
          complete = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule { options = choiceOptions; });
            default = [ ];
            description = "Completions for the first argument.";
          };
        };
      };

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

      hmCache = pkgs.stubbe.bashApp {
        name = "hm-cache";
        text = ''
          usage() {
            echo "Usage: hm cache <target>, target one of: ${cacheTargetNames}"
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
              echo "hm cache: unknown target '$1' (want ${cacheTargetNames})" >&2
              exit 2
              ;;
          esac
        '';
      };

      hmClean = pkgs.stubbe.bashApp {
        name = "hm-clean";
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

          menu=($'(action)\tNix store garbage: old generations + unreachable paths (runs: hm gc)')
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
            echo "hm clean: nothing selected"
            exit 0
          fi

          echo
          echo "About to remove:"
          printf '  %s\n' "''${selection//$'\n'/$'\n'  }"
          read -rp "Proceed? [y/N] " confirm
          if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "hm clean: aborted"
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
            ${lib.getExe pkgs.stubbe.hm} gc
          fi

          echo "Done."
        '';
      };

      cachePush = pkgs.stubbe.bashApp {
        name = "hm-cache-push";
        runtimeInputs = [
          pkgs.sops
          pkgs.xilo
        ];
        text = ''
          generation="$1"
          token_file="$HM_FLAKE/secrets/xilo-token"
          if [ ! -f "$token_file" ]; then
            echo "cache push: secrets/xilo-token missing, run 'hm secret set xilo-token'. Skipping." >&2
            exit 0
          fi
          token=$(sops --decrypt --input-type binary --output-type binary "$token_file")
          echo "Pushing ''${generation##*/} closure to the cache…"
          XILO_URL="https://nix.stubbe.dev" XILO_TOKEN="$token" xilo push default "$generation" --quiet
        '';
      };
    in
    {
      options.stubbe.hm = {
        commands = lib.mkOption {
          type = lib.types.listOf commandType;
          default = [ ];
          description = ''
            Extra `hm` subcommands: `hm <name> [args]` runs `exec` with the
            arguments, and `hm help` and the completion list them.
          '';
        };

        postSwitch = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Programs `hm switch` and `hm upgrade` run after a successful
            activation, with the activated generation as the argument and
            HM_FLAKE set to the flake directory.
          '';
        };

        settings = lib.mkOption {
          type = lib.types.attrs;
          readOnly = true;
          internal = true;
          description = "The `hm` config file contents, rendered to ~/.config/hm/config.json.";
        };
      };

      config = {
        stubbe.hm = {
          commands = [
            {
              name = "clean";
              description = "Interactive fzf TUI to reclaim disk space (build dirs, caches, core dumps, nix gc) under [dir], default $HOME";
              exec = lib.getExe hmClean;
            }
            {
              name = "cache";
              description = "Wipe cached state (target: ${cacheTargetNames})";
              exec = lib.getExe hmCache;
              complete = lib.mapAttrsToList (name: target: {
                inherit name;
                inherit (target) description;
              }) cacheTargets;
            }
          ];
          postSwitch = lib.optional config.features.development (lib.getExe cachePush);
          settings = {
            flake = config.stubbe.paths.dotfiles;
            inherit (config.host) platform;
            attr = config.host.flakeAttr;
            ssh_key = "${config.home.homeDirectory}/.ssh/id_ed25519";
            hooks.post_switch = config.stubbe.hm.postSwitch;
            inherit (config.stubbe.hm) commands;
          };
        };

        home.packages = [ pkgs.stubbe.hm ];
        xdg.configFile."hm/config.json".source =
          (pkgs.formats.json { }).generate "hm-config.json"
            config.stubbe.hm.settings;
      };
    };
}
