# A declared option, not `flake.lib` alone: reading a freeform flake attr forces
# the whole `flake` submodule, including perSystem outputs that need `pkgs`,
# which is built from the overlays that read this. `flake.lib` is only a mirror.
{
  config,
  self,
  lib,
  ...
}:
{
  options.stubbe.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "Pure data and pure functions shared across every class. Re-exported as `pkgs.stubbe`.";
  };

  config.flake.lib = config.stubbe.lib;

  config.stubbe.lib = {
    src = self;
  };
}
