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
      };
    };
}
