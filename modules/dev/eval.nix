{ self, ... }:
{
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
