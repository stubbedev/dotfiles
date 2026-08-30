{ config, inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  systems = [ "x86_64-linux" ];

  # One nixpkgs instantiation, shared by the standalone-HM target here and
  # mirrored into NixOS's `nixpkgs.*` (modules/nix.nix) from the same
  # `stubbe.lib.nixpkgsConfig` — so a `pkgs.<x>` reference resolves to the same
  # This module deliberately declares NOTHING else per-system: a perSystem
  # output declared here would depend on `pkgs`, which is built below from
  # `config.flake.overlays`, whose evaluation forces the transposed perSystem
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config = config.stubbe.lib.nixpkgsConfig;
        overlays = builtins.attrValues config.flake.overlays;
      };
    };
}
