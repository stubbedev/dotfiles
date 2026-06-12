{ self, ... }:
{
  # Static analysis over the whole repo. statix catches Nix anti-patterns
  # (repeated keys, empty patterns, manual inherits); deadnix catches
  # unused bindings and function arguments. Both run read-only against
  # the flake source in the store, so the checks are pure and cheap.
  perSystem =
    { pkgs, ... }:
    {
      checks = {
        lint-statix = pkgs.runCommand "lint-statix" { nativeBuildInputs = [ pkgs.statix ]; } ''
          statix check ${self}
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
      };
    };
}
