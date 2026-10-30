{ inputs, ... }:
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
      nodeCaBundle = "${config.xdg.cacheHome}/node/extra-ca.pem";
    in
    {
      imports = [ inputs.direnv-instant.homeModules.direnv-instant ];

      config = lib.mkIf config.features.development {
        home.sessionVariables.NODE_EXTRA_CA_CERTS = nodeCaBundle;

        home.file.".prettierrc.json".source = pkgs.stubbe.gen.json "prettierrc.json" {
          printWidth = 80;
          useTabs = true;
          singleQuote = true;
          overrides = [
            {
              files = [
                "*.md"
                "*.mdx"
              ];
              options = {
                proseWrap = "always";
                printWidth = 80;
              };
            }
          ];
        };

        # Language toolchains (go, rust, the C/C++ linker stack) are deliberately
        # absent: each repo's flake dev shell owns them, loaded by direnv on cd.
        # Only what is repo-agnostic stays.
        home.packages =
          with pkgs;
          [
            nodejs_24
            pnpm

            python3
          ]
          ++ lib.optionals config.features.desktop [
            # gfx.bundle, not a bare wrap: a bare nixGL wrap emits only bin/, losing
            # the .desktop entry rofi needs.
            (gfx.bundle { pkg = pkgs.neovide; })
            # NIXOS_OZONE_WL makes nixpkgs' wrapper pass Chromium switches that
            # the code CLI warns about; --ozone-platform is one it knows. Without
            # it Electron's auto-detection falls back to XWayland, as the session
            # sets no XDG_SESSION_TYPE.
            (gfx.bundle {
              pkg = pkgs.vscode;
              flags = [ "--ozone-platform=wayland" ];
            })
          ];

        stubbe.setup.vscodeApparmor = pkgs.stubbe.setup.apparmor {
          appName = "VS Code";
          profileName = "nix-vscode";
          programGlob = "/nix/store/*/lib/vscode/{code,chrome-sandbox}";
        };

        programs = {
          uv.enable = true;

          # silent drops status lines only; errors still print. The zsh hook
          # is direnv-instant's (below).
          direnv = {
            enable = true;
            enableZshIntegration = false;
            silent = true;
            enableGitIntegration = true;
            nix-direnv.enable = true;
            config = {
              global = {
                hide_env_diff = true;
                warn_timeout = "0s";
              };
              whitelist.prefix = [ "/" ];
            };
          };

          # Takes over direnv's shell hook: the prompt returns at once and the
          # environment lands when the daemon signals, from cache on revisit.
          # An evaluation over mux_delay opens a tmux pane with its output.
          # modules/shell.nix sources a zcompiled hook; HM's runtime eval would
          # inject a duplicate.
          direnv-instant = {
            enable = true;
            enableZshIntegration = false;
          };
        };

        stubbe.setup.nodeCaBundle.script = ''
          export PATH="${
            lib.makeBinPath [
              pkgs.gawk
              pkgs.findutils
              pkgs.coreutils
            ]
          }:$PATH"

          bundle="${nodeCaBundle}"
          bundle_dir="${dirOf nodeCaBundle}"
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
            add_file "${config.xdg.dataHome}/mkcert/rootCA.pem"
            local sites_dir="${config.xdg.configHome}/srv/sites"
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
                PATH="${lib.makeBinPath [ pkgs.coreutils ]}:$PATH"

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
                  docker="${lib.getExe pkgs.docker}"
                  "$docker" builder prune -f >/dev/null
                  "$docker" image prune -f >/dev/null

                  "$docker" volume ls -f dangling=true -q \
                    | "$grep" -E '^[0-9a-f]{64}$' \
                    | while IFS= read -r v; do "$docker" volume rm "$v" >/dev/null; done

                  "$docker" volume ls -q | "$grep" -E '^buildx_buildkit_.*_state$' \
                    | while IFS= read -r v; do
                        b="''${v#buildx_buildkit_}"
                        b="''${b%0_state}"
                        if ! "$docker" buildx inspect "$b" >/dev/null 2>&1; then
                          echo "rm orphaned buildx state: $v"
                          "$docker" volume rm "$v" >/dev/null
                        fi
                      done
                ''}
              '';
              Nice = 19;
              IOSchedulingClass = "idle";
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
    };
}
