_: {
  flake.modules.homeManager.xdgAerc =
    {
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      xdg.configFile = homeLib.xdgSources [
        "aerc/aerc.conf"
        "aerc/binds.conf"
      ];
    };
}
