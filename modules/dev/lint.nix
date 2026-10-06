{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      apps.lint-fix.program = pkgs.writeShellApplication {
        name = "lint-fix";
        runtimeInputs = [
          pkgs.statix
          pkgs.deadnix
          pkgs.nixfmt
          pkgs.git
        ];
        # Scoped to tracked files, which is exactly what ends up in the flake
        # source the checks run against. Walking `.` instead would follow the
        # result/ symlinks into the read-only store. Deleted-but-unstaged
        # files are filtered out: until the deletion is committed they still
        # show up in git ls-files, and deadnix/nixfmt die on the missing
        # paths.
        text = ''
          cd "$(git rev-parse --show-toplevel)"
          statix fix .
          tracked_nix() {
            git ls-files -z '*.nix' \
              | while IFS= read -r -d "" f; do
                if [ -e "$f" ]; then printf '%s\0' "$f"; fi
              done
          }
          tracked_nix | xargs -0 -r deadnix --edit --
          tracked_nix | xargs -0 -r nixfmt
        '';
      };

      checks = {
        # -c is required: statix reads statix.toml from the config path only,
        # and does not discover it inside the target directory.
        lint-statix = pkgs.stubbe.check {
          name = "lint-statix";
          nativeBuildInputs = [ pkgs.statix ];
          text = ''
            statix check -c ${self} ${self}
            touch "$out"
          '';
        };

        lint-deadnix = pkgs.stubbe.check {
          name = "lint-deadnix";
          nativeBuildInputs = [ pkgs.deadnix ];
          text = ''
            deadnix --fail -- ${self}
            touch "$out"
          '';
        };

        lint-fmt = pkgs.stubbe.check {
          name = "lint-fmt";
          nativeBuildInputs = [ pkgs.nixfmt ];
          text = ''
            find ${self} -name '*.nix' -print0 | xargs -0 nixfmt --check
            touch "$out"
          '';
        };

        lint-shellcheck = pkgs.stubbe.check {
          name = "lint-shellcheck";
          nativeBuildInputs = [ pkgs.shellcheck ];
          text = ''
            shellcheck -S warning ${self}/bin/stb-install ${self}/bin/stb-install-nixos
            touch "$out"
          '';
        };
      };
    };
}
