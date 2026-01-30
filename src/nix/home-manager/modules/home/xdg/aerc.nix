{ ... }:
{
  flake.modules.homeManager.xdgAerc = { homeLib, ... }: {
    xdg.configFile = homeLib.xdgSources [
      "aerc/aerc.conf"
      "aerc/binds.conf"
    ];
  };
}
