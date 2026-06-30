{ config, inputs, ... }:
let
  mkPkgs =
    system:
    import inputs.nixpkgs {
      inherit system;
      # Mirror modules/nixos/nix-settings.nix so standalone-HM and NixOS
      # builds resolve packages against the same nixpkgs config.
      config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          "dcraw-9.28.0"
          "pnpm-10.34.0"
        ];
      };
      overlays = builtins.attrValues config.flake.overlays;
    };
in
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = mkPkgs system;
    };
}
