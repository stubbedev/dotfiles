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
    in
    lib.mkIf config.features.development {
      home.packages =
        with pkgs;
        [
          # Pinned: the work monorepo sets engines.node 24.x and yarn 1 hard-fails
          # on a mismatch, so yarn has to run under the same node.
          nodejs_24
          bun
          pnpm
          (yarn.override { nodejs = nodejs_24; })
          deno

          prettier
          oxlint
          oxfmt
          stylua

          gopass
          gotools
          air
          templ
          golangci-lint

          mongodb-tools
          mongosh
          redis # provides redis-cli

          c3c
          caddy
          freerdp
          openconnect

          mold
          # gcc also ships a `cc`.
          (lib.setPrio 15 clang)
          sccache
          cargo-sweep
          cargo-nextest # preferred test runner: `cargo nextest run`
        ]
        ++ [
          # gfx.bundle, not a bare wrap: a bare nixGL wrap emits only bin/, losing
          # the .desktop entry rofi needs.
          (gfx.bundle { pkg = pkgs.neovide; })
        ]
        ++
          lib.optional config.features.rust
            inputs.fenix.packages.${pkgs.stdenv.hostPlatform.system}.stable.toolchain;

      programs = {
        go = {
          enable = true;
          package = pkgs.go_latest;
          # GOBIN stays unset so it defaults to $GOPATH/bin, which modules/shell.nix
          # keeps OFF PATH: `go install` must not shadow nix-pinned tooling.
          env.GOPATH = "${config.home.homeDirectory}/.go";
        };

        uv.enable = true;

        direnv = {
          enable = true;
          nix-direnv.enable = true;
          # modules/shell.nix already sources a zcompiled hook; HM's would inject
          # a duplicate after it.
          enableZshIntegration = false;
          # log_filter is an ALLOWLIST, so a never-matching regex suppresses every
          # status line. Errors bypass it entirely and still surface.
          config.global.log_filter = "$.";
        };
      };

      home.sessionVariables.GOROOT = "${config.programs.go.package}/share/go";

      # Deliberately not npm_config_store_dir: npm scans every npm_config_*
      # variable, has no `store-dir` key, and warns on every invocation.
      # A dev container mounting ~/.config/pnpm can leave an unmanaged file here.
      xdg.configFile."pnpm/rc" = {
        force = true;
        text = ''
          store-dir=${config.home.homeDirectory}/.local/share/pnpm/store
        '';
      };

      # Holds the auth token in plaintext, so it is sops-encrypted and the login
      # survives rebuilds. Re-encrypt after `npm login` writes a fresh token.
      sops.secrets.npmrc = pkgs.stubbe.secret {
        name = "npmrc";
        path = "${config.home.homeDirectory}/.npmrc";
      };

      stubbe.setup.nodeCaBundle.script = ''
        # Activations run with a stripped PATH; awk (gawk) and find/xargs
        # (findutils) are not on it, and without them the dedup pass below
        # fails and the bundle is left as-is.
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

        add_valet_paths() {
          for dir in \
            "$HOME/.valet" \
            "$HOME/.config/valet" \
            "''${XDG_DATA_HOME:-$HOME/.local/share}/valet" \
            "''${XDG_CONFIG_HOME:-$HOME/.config}/valet"; do
            [ -d "$dir" ] || continue
            add_dir "$dir/CA"
            add_dir "$dir/Certificates"
          done
        }

        add_srv_paths() {
          add_file "''${XDG_DATA_HOME:-$HOME/.local/share}/mkcert/rootCA.pem"
          local sites_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/srv/sites"
          [ -d "$sites_dir" ] || return 0
          for site_dir in "$sites_dir"/*/; do
            add_dir "$site_dir/certs"
          done
        }

        # 1. The OS trust store — always present, valid PEM, and already
        #    includes the mkcert CA. Seeding with it guarantees a non-empty
        #    bundle so the runtime (BoringSSL, via Claude Code) never warns at
        #    launch: a missing file fails with errno 2 ("system library"), an
        #    empty one with "PEM routines".
        add_file "${config.home.sessionVariables.SSL_CERT_FILE}"

        # 2. The mkcert root, in case the OS store predates the current CA.
        if [ -n "''${CAROOT-}" ]; then
          add_file "''${CAROOT}/rootCA.pem"
        fi
        if command -v mkcert >/dev/null 2>&1; then
          caroot="$(mkcert -CAROOT 2>/dev/null || true)"
          [ -n "$caroot" ] && add_file "$caroot/rootCA.pem"
        fi

        # 3. valet + srv leaf/CA certs, which are not in the OS store.
        add_valet_paths
        ${lib.optionalString config.features.srv "add_srv_paths"}

        # Collapse to unique CERTIFICATE blocks, dropping comments and the
        # OS-store/mkcert-root overlap. BoringSSL stops at the first
        # unparseable block, so emit only clean cert PEM.
        awk '
          /-----BEGIN CERTIFICATE-----/ { inblk = 1; blk = "" }
          inblk { blk = blk $0 "\n" }
          /-----END CERTIFICATE-----/ { inblk = 0; if (!seen[blk]++) printf "%s", blk }
        ' "$tmp" > "$tmp.dedup" && mv "$tmp.dedup" "$tmp"

        # Publish only a non-empty result; otherwise keep the last good bundle
        # rather than leaving the path missing, which is what triggers the warn.
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
            ExecStart = pkgs.writeShellScript "dev-cleanup" ''
              set -u

              find="${lib.getExe' pkgs.findutils "find"}"
              grep="${lib.getExe' pkgs.gnugrep "grep"}"

              # --- Cargo: stale target/ dirs under ~/git ------------------
              # mtime +30: untouched for 30 days. A sibling Cargo.toml confirms
              # we never nuke a coincidentally-named `target` dir. -prune stops
              # find descending into the (huge) match before we remove it.
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
                  # Build cache: nothing references it once a build finishes.
                  "$docker" builder prune -f >/dev/null 2>&1 || true
                  # Dangling (untagged) image layers only — never tagged images.
                  "$docker" image prune -f >/dev/null 2>&1 || true

                  # Anonymous volumes (64-hex names) with no container attached.
                  # Named volumes are skipped by the regex — they may hold data.
                  "$docker" volume ls -f dangling=true -q 2>/dev/null \
                    | "$grep" -E '^[0-9a-f]{64}$' \
                    | while IFS= read -r v; do "$docker" volume rm "$v" >/dev/null 2>&1 || true; done

                  # Orphaned buildx builder state: buildx_buildkit_<name>0_state
                  # whose <name> is no longer a registered builder.
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
