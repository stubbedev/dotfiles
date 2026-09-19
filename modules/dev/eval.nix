{ self, ... }:
{
  # Note: graphics.nix requires --impure for GPU detection, so run
  # `nix flake check --impure` (same constraint as nixos-rebuild here).
  perSystem =
    { pkgs, ... }:
    {
      checks = {
        eval-nixos-stubbe = pkgs.stubbe.check {
          name = "eval-nixos-stubbe";
          env.toplevel = builtins.unsafeDiscardStringContext self.nixosConfigurations.stubbe-nixos.config.system.build.toplevel.drvPath;
          text = ''
            echo "evaluated: $toplevel" > "$out"
          '';
        };

        eval-hm-stubbe = pkgs.stubbe.check {
          name = "eval-hm-stubbe";
          env.toplevel = builtins.unsafeDiscardStringContext self.homeConfigurations.stubbe.activationPackage.drvPath;
          text = ''
            echo "evaluated: $toplevel" > "$out"
          '';
        };
      };
    };
}
