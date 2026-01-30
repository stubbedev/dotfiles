{ ... }:
{
  flake.modules.homeManager.programsUv = { lib, config, ... }:
    lib.mkIf config.features.development {
      programs.uv = { enable = true; };
    };
}
