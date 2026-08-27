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
        text = ''
          cd "$(git rev-parse --show-toplevel)"
          statix fix .
          git ls-files -z '*.nix' \
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

        # No exclusions: with the activation factory gone, every module names
        # only the arguments it actually uses.
        lint-deadnix = pkgs.runCommand "lint-deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
          deadnix --fail -- ${self}
          touch "$out"
        '';

        # Formatting drift fails the check; fix with `nix fmt`.
        lint-fmt = pkgs.runCommand "lint-fmt" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
          find ${self} -name '*.nix' -print0 | xargs -0 nixfmt --check
          touch "$out"
        '';

        # Only the two pre-Nix bootstraps are still real script files; every
        # other script is inline nix and gets its shellcheck (bashApp) or
        # `zsh -n` (zshApp) at build time in pkgs.stubbe.
        lint-shellcheck = pkgs.runCommand "lint-shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
          shellcheck -S warning ${self}/bin/stb-install ${self}/bin/stb-install-nixos
          touch "$out"
        '';
      };
    };
}
