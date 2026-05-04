{ config, inputs, ... }:
let
  mkPkgs =
    system:
    import inputs.nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        allowUnfreePredicate = _: true;
        allowInsecure = true;
        allowInsecurePredicate = _: true;
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
