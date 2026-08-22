{ self, ... }:
{
  # Static analysis over the whole repo. statix catches Nix anti-patterns
  # (empty patterns, manual inherits — see statix.toml for what's turned
  # off); deadnix catches unused bindings and function arguments. Both run
  # read-only against the flake source in the store, so the checks are pure
  # and cheap. `nix run .#lint-fix` below applies the machine-fixable subset.
  perSystem =
    { pkgs, ... }:
    {
      # `nix run .#lint-fix` applies every fix the linters can apply
      # themselves, in the working tree. CI runs this before the checks and
      # commits the result, so formatting and dead-code drift never costs a
      # round trip. Uses the same pkgs as the checks below — a fixer on a
      # different tool version than the checker can disagree with it.
      #
      # shellcheck has no reliable fixer (its --format=diff patches are
      # partial), so bin/ findings still have to be fixed by hand.
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
        # result/ and .direnv symlinks into the read-only store.
        #
        # _helpers.nix is filtered out here rather than passed to deadnix
        # --exclude: that flag only prunes directory traversal, so with an
        # explicit file list deadnix would strip the very arguments the check
        # below excludes it to protect.
        text = ''
          cd "$(git rev-parse --show-toplevel)"
          statix fix .
          git ls-files -z '*.nix' \
            | grep -zv '^modules/activation/_helpers\.nix$' \
            | xargs -0 deadnix --edit --
          git ls-files -z '*.nix' | xargs -0 nixfmt
        '';
      };

      checks = {
        # -c is required: statix reads statix.toml from the config path only,
        # and does not discover it inside the target directory.
        lint-statix = pkgs.runCommand "lint-statix" { nativeBuildInputs = [ pkgs.statix ]; } ''
          statix check -c ${self} ${self}
          touch "$out"
        '';

        # _helpers.nix is excluded: its module lambdas name config/pkgs/
        # homeLib without referencing them directly, because the module
        # system only injects args NAMED in the pattern — `...`/@moduleArgs
        # does not pull in undeclared ones, and `args moduleArgs` needs
        # them downstream. deadnix has no inline skip directive.
        lint-deadnix = pkgs.runCommand "lint-deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
          deadnix --fail --exclude ${self}/modules/activation/_helpers.nix -- ${self}
          touch "$out"
        '';

        # Formatting drift fails the check; fix with `nix fmt`.
        lint-fmt = pkgs.runCommand "lint-fmt" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
          find ${self} -name '*.nix' -print0 | xargs -0 nixfmt --check
          touch "$out"
        '';

        # shellcheck only understands sh/bash/dash/ksh — the zsh scripts
        # in bin/ are skipped (SC1071 territory), bash ones are enforced
        # at warning severity.
        lint-shellcheck = pkgs.runCommand "lint-shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
          status=0
          for f in ${self}/bin/*; do
            if head -n1 "$f" | grep -q 'bash'; then
              shellcheck -S warning "$f" || status=1
            fi
          done
          [ "$status" -eq 0 ]
          touch "$out"
        '';

        # The other half of bin/: zsh scripts shellcheck refuses to read. `zsh
        # -n` is only a parse, but it is the one check that runs over them at
        # all, and it also covers the zsh files sourced into every shell —
        # a syntax error there breaks login, not just one command.
        lint-zsh-parse = pkgs.runCommand "lint-zsh-parse" { nativeBuildInputs = [ pkgs.zsh ]; } ''
          status=0
          for f in ${self}/bin/* ${self}/src/zsh/*; do
            [ -f "$f" ] || continue
            case "$f" in
              *.md | *.json) continue ;;
            esac
            if head -n1 "$f" | grep -q zsh || [ "''${f#${self}/src/zsh/}" != "$f" ]; then
              zsh -n "$f" || { echo "zsh -n failed: $f" >&2; status=1; }
            fi
          done
          [ "$status" -eq 0 ]
          touch "$out"
        '';
      };
    };
}
