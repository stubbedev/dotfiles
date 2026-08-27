_: {
  flake.modules.homeManager.homeXdgAerc =
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
        "aerc/scripts"
      ];
    };
}
