{ config, inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  systems = [ "x86_64-linux" ];

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
