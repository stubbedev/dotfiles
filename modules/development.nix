{ ... }:
{
  flake.modules.homeManager.development =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.stubbe) gfx;
    in
    lib.mkIf config.features.development {
      # Language toolchains (go, rust, the C/C++ linker stack) are deliberately
      # absent: each repo's devenv owns them. Only what is repo-agnostic stays.
      home.packages =
        with pkgs;
        [
          nodejs_24

          prettier
          oxlint
          oxfmt
          stylua

          python3
        ]
        ++ [
          # gfx.bundle, not a bare wrap: a bare nixGL wrap emits only bin/, losing
          # the .desktop entry rofi needs.
          (gfx.bundle { pkg = pkgs.neovide; })
        ];

      programs = {
        uv.enable = true;

        devenv = {
          enable = true;
          # modules/shell.nix already sources a zcompiled hook; HM's runtime
          # eval would inject a duplicate after it.
          enableZshIntegration = false;
        };
      };

      # devenv reads this for shell/TUI preferences. The schema rejects
      # unknown keys, so a stale key would break every devenv invocation:
      # keep it to settings that exist. Kills the "(devenv)" prompt prefix;
      # TUI/watcher silencing lives in the hook flags (modules/shell.nix).
      xdg.configFile."devenv/config.yaml".text = ''
        version: 1
        shell:
          prompt_prefix: false
      '';

      stubbe.setup.nodeCaBundle.script = ''
        export PATH="${
          lib.makeBinPath [
            pkgs.gawk
            pkgs.findutils
            pkgs.coreutils
          ]
        }:$PATH"

        bundle="${config.home.sessionVariables.NODE_EXTRA_CA_CERTS}"
        bundle_dir="${dirOf config.home.sessionVariables.NODE_EXTRA_CA_CERTS}"
        tmp="$bundle.tmp"

        mkdir -p "$bundle_dir"
        : > "$tmp"

        add_file() {
          [ -f "$1" ] || return 0
          cat "$1" >> "$tmp"
        }

        add_dir() {
          [ -d "$1" ] || return 0
          find "$1" -maxdepth 1 \( -name '*.pem' -o -name '*.crt' -o -name '*.cer' \) -type f -print0 |
            xargs -0 -r cat >> "$tmp"
        }

        add_srv_paths() {
          add_file "''${XDG_DATA_HOME:-$HOME/.local/share}/mkcert/rootCA.pem"
          local sites_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/srv/sites"
          [ -d "$sites_dir" ] || return 0
          for site_dir in "$sites_dir"/*/; do
            add_dir "$site_dir/certs"
          done
        }

        add_file "${config.home.sessionVariables.SSL_CERT_FILE}"

        # The srv CA rides in via add_srv_paths below: srv vendors mkcert (same
        # CAROOT layout), so no standalone mkcert binary exists on PATH.
        ${lib.optionalString config.features.srv "add_srv_paths"}

        awk '
          /-----BEGIN CERTIFICATE-----/ { inblk = 1; blk = "" }
          inblk { blk = blk $0 "\n" }
          /-----END CERTIFICATE-----/ { inblk = 0; if (!seen[blk]++) printf "%s", blk }
        ' "$tmp" > "$tmp.dedup" && mv "$tmp.dedup" "$tmp"

        if [ -s "$tmp" ]; then
          mv "$tmp" "$bundle"
        else
          rm -f "$tmp"
        fi
      '';

      systemd.user = {
        services.dev-cleanup = {
          Unit.Description = "Prune dev build artifacts (cargo targets, docker cache/volumes)";
          Service = {
            Type = "oneshot";
            ExecStart = pkgs.stubbe.shellScript "dev-cleanup" ''
              set -u

              find="${lib.getExe' pkgs.findutils "find"}"
              grep="${lib.getExe' pkgs.gnugrep "grep"}"

              "$find" "$HOME/git" -mindepth 2 -maxdepth 6 -type d -name target -mtime +30 -prune -print0 2>/dev/null \
                | while IFS= read -r -d "" t; do
                    if [ -f "$(dirname "$t")/Cargo.toml" ]; then
                      echo "rm stale cargo target: $t"
                      rm -rf "$t"
                    fi
                  done

              ${lib.optionalString config.features.docker ''
                docker="$(command -v docker || true)"
                if [ -n "$docker" ]; then
                  "$docker" builder prune -f >/dev/null 2>&1 || true
                  "$docker" image prune -f >/dev/null 2>&1 || true

                  "$docker" volume ls -f dangling=true -q 2>/dev/null \
                    | "$grep" -E '^[0-9a-f]{64}$' \
                    | while IFS= read -r v; do "$docker" volume rm "$v" >/dev/null 2>&1 || true; done

                  "$docker" volume ls -q 2>/dev/null | "$grep" -E '^buildx_buildkit_.*_state$' \
                    | while IFS= read -r v; do
                        b="''${v#buildx_buildkit_}"
                        b="''${b%0_state}"
                        if ! "$docker" buildx inspect "$b" >/dev/null 2>&1; then
                          echo "rm orphaned buildx state: $v"
                          "$docker" volume rm "$v" >/dev/null 2>&1 || true
                        fi
                      done
                fi
              ''}
            '';
            Nice = 19;
            IOSchedulingClass = "idle";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin"
            ];
          };
        };

        timers.dev-cleanup = {
          Unit.Description = "Weekly dev build-artifact cleanup";
          Timer = {
            OnCalendar = "weekly";
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
