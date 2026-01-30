{ ... }:
{
  flake.modules.homeManager.programsGo = { lib, config, ... }:
    lib.mkIf config.features.development {
      programs.go = { enable = true; };
    };
}
