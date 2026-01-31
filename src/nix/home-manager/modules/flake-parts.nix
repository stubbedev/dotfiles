{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  perSystem =
    { pkgs, ... }:
    {
      formatter = pkgs.nixpkgs-fmt;
    };
}
