{ self, ... }:
{
  # Every flake.modules.homeManager.* module flows into BOTH targets:
  # the NixOS system (via the HM bridge) and standalone home-manager on
  # non-NixOS hosts. A module that evaluates on one can still break the
  # other, so force a full eval of both toplevels at check time.
  #
  # unsafeDiscardStringContext keeps these eval-only: the check forces
  # the complete module evaluation (drvPath), but drops the store-path
  # context so `nix flake check` does not build either closure.
  #
  # Note: graphics.nix requires --impure for GPU detection, so run
  # `nix flake check --impure` (same constraint as nixos-rebuild here).
  perSystem =
    { pkgs, ... }:
    {
      checks = {
        eval-nixos-stubbe =
          pkgs.runCommand "eval-nixos-stubbe"
            {
              toplevel = builtins.unsafeDiscardStringContext self.nixosConfigurations.stubbe-nixos.config.system.build.toplevel.drvPath;
            }
            ''
              echo "evaluated: $toplevel" > "$out"
            '';

        eval-hm-stubbe =
          pkgs.runCommand "eval-hm-stubbe"
            {
              toplevel = builtins.unsafeDiscardStringContext self.homeConfigurations.stubbe.activationPackage.drvPath;
            }
            ''
              echo "evaluated: $toplevel" > "$out"
            '';
      };
    };
}
