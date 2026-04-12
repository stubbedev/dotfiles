_: {
  flake.modules.homeManager.xdgNiri =
    {
      config,
      lib,
      homeLib,
      ...
    }:
    lib.mkIf config.features.niri {
      xdg.configFile =
        homeLib.xdgSources [
          "niri/config.kdl"
          "niri/hypridle.conf"
          "niri/scripts"
        ];
    };
}
