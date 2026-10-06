{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # `nix flake check` evaluates every nixosConfigurations toplevel
      # natively, but never touches homeConfigurations, so the standalone
      # host needs its own eval guard.
      checks.eval-hm-stubbe = pkgs.stubbe.check {
        name = "eval-hm-stubbe";
        env.toplevel = builtins.unsafeDiscardStringContext self.homeConfigurations.stubbe.activationPackage.drvPath;
        text = ''
          echo "evaluated: $toplevel" > "$out"
        '';
      };
    };
}
